#!/usr/bin/env bash
# Resilient kubectl port-forward supervisor for the smoke test.
#
# kubectl port-forward tunnels through a single SPDY/TCP stream. Managed
# cloud load balancers and some CNIs (EKS, AKS ILB, ...) reap that stream
# after a short idle window (as low as ~30-60s). A bare one-shot
# `kubectl port-forward` then exits and is never restarted, so every
# subsequent request returns HTTP 000 even though Camunda is healthy
# (observed on EKS single-region: 0/30 verify attempts reached the
# search API). This wrapper restarts the forward whenever it exits, until
# the caller drops the stop sentinel, keeping the local port usable for
# the whole smoke test.
#
# Usage:
#   port-forward.sh <namespace> <target> <ports> <base>
#
# Derived from <base>:
#   <base>.log   kubectl + supervisor output
#   <base>.pid   supervisor PID (also its process-group id, via setsid)
#   <base>.stop  stop sentinel — `touch` it to stop restarting. The
#                supervisor stops relaunching kubectl and exits once the
#                running kubectl invocation ends; the cleanup step also
#                kills the process group directly for prompt teardown.
#
# Example:
#   port-forward.sh camunda svc/camunda-zeebe-gateway 8080:8080 \
#       /tmp/smoke-pf/zeebe
#
# Intentionally no `set -e`: a dropped port-forward must restart, not
# abort the supervisor.
set -uo pipefail

if [[ "$#" -ne 4 ]]; then
    echo "usage: port-forward.sh <namespace> <target> <ports> <base>" >&2
    exit 2
fi

NS="$1"
TARGET="$2"
PORTS="$3"
BASE="$4"

LOG="${BASE}.log"
PIDFILE="${BASE}.pid"
STOP="${BASE}.stop"

# Record our own PID so the cleanup step can kill this supervisor and its
# kubectl child as a process group (setsid makes this PID the group lead).
echo "$$" >"$PIDFILE"

# Start each run with a clean log and no stale stop sentinel, so reused
# (self-hosted) runners don't mix output from previous runs.
: >"$LOG"
rm -f "$STOP"

restart=0
while [[ ! -f "$STOP" ]]; do
    if [[ "$restart" -gt 0 ]]; then
        echo "[pf-supervisor] $(date -u +%H:%M:%S) restart #${restart}: kubectl port-forward ${TARGET} ${PORTS} -n ${NS}" >>"$LOG"
    else
        echo "[pf-supervisor] $(date -u +%H:%M:%S) starting: kubectl port-forward ${TARGET} ${PORTS} -n ${NS}" >>"$LOG"
    fi

    kubectl port-forward "$TARGET" "$PORTS" -n "$NS" </dev/null >>"$LOG" 2>&1 || true

    # Asked to stop while kubectl was running: exit without restarting.
    [[ -f "$STOP" ]] && break

    restart=$((restart + 1))
    echo "[pf-supervisor] $(date -u +%H:%M:%S) port-forward exited; restarting in 1s" >>"$LOG"
    sleep 1
done

echo "[pf-supervisor] $(date -u +%H:%M:%S) stop sentinel found; exiting after ${restart} restart(s)" >>"$LOG"
