#!/usr/bin/env bash
# kubectl port-forward lifecycle shared by the CI composite actions.
#
# kubectl port-forward tunnels through a single SPDY/TCP stream. Managed
# cloud load balancers and some CNIs (EKS, AKS ILB, ...) reap that stream
# after a short idle window (as low as ~30-60s). A bare one-shot
# `kubectl port-forward` then exits and is never restarted, so every
# subsequent request returns HTTP 000 / connection-refused even though
# Camunda is healthy (observed on EKS single-region: 0/30 verify attempts
# reached the search API; #2970 reported the same on the actuator port).
# `supervise` restarts the forward whenever it exits, until the caller
# drops the stop sentinel.
#
# Usage:
#   port-forward.sh start <namespace> <target> <ports> <base>
#   port-forward.sh wait  <base> <local-port> [attempts]
#   port-forward.sh stop  <dir>
#   port-forward.sh supervise <namespace> <target> <ports> <base>
#   port-forward.sh selftest
#
# `supervise` is the long-running loop; `start` re-execs this script into it
# under setsid + nohup, so it survives the composite-action step boundary and
# becomes its own process-group leader (killable as a group).
#
# Derived from <base>:
#   <base>.log   kubectl + supervisor output
#   <base>.pid   supervisor PID (also its process-group id, via setsid)
#   <base>.stop  stop sentinel — `touch` it to stop restarting. The
#                supervisor stops relaunching kubectl and exits once the
#                running kubectl invocation ends; `stop` also kills the
#                process group directly for prompt teardown.
#
# Example:
#   port-forward.sh start camunda svc/camunda-zeebe-gateway 8080:8080 \
#       /tmp/smoke-pf/zeebe
#   port-forward.sh wait /tmp/smoke-pf/zeebe 8080
#   port-forward.sh stop /tmp/smoke-pf
#
# Intentionally no `set -e`: a dropped port-forward must restart, not abort
# the supervisor, and the teardown paths tolerate processes that already
# exited. Every subcommand reports failure through its return code.
set -uo pipefail

# Seconds a single kubectl attempt gets to bind before it is recycled, and
# attempts `wait` polls for (1s apart). The wait budget has to outlast at least
# two bind deadlines so a first hung attempt is not fatal.
PF_BIND_TIMEOUT="${PF_BIND_TIMEOUT:-15}"
PF_WAIT_ATTEMPTS="${PF_WAIT_ATTEMPTS:-60}"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# True when <pid> is the supervisor for <base>. A PID file alone proves
# nothing: the supervisor may have exited and its PID been recycled, possibly
# by another live supervisor, and signalling that one's process group would
# tear down an unrelated forward.
pf_owns() {
    local pid="$1" base="$2" argv
    [[ -n "$pid" ]] || return 1
    argv=$(ps -o args= -p "$pid" 2>/dev/null || true)
    [[ "$argv" == *"port-forward.sh"* && "$argv" == *"$base"* ]]
}

# Classify the currently running attempt as ready / bind-error / waiting.
#
# The supervisor appends every restart to one log, so a "Forwarding from"
# line left by an attempt that has since exited must not count as ready, and
# a collision reported by an earlier attempt must not fail a healthy current
# one. Only the attempt banners reset the verdict: the "port-forward exited"
# line has to stay visible, because it is what invalidates a marker seen
# earlier in the same attempt.
#
# The readiness marker is kubectl's own, written only after a successful
# bind, so it is positive proof that this forward owns the port. An open port
# proves nothing: a stale kubectl or unrelated service holding it would
# satisfy a plain TCP probe just as well and the tests would run against the
# squatter. Same marker the Go kubectl helper scans for, see
# aws/kubernetes/eks-dual-region/test/internal/helpers/kubectl/helpers.go.
#
# Readiness outranks the bind error in END. Both failure patterns come from a
# single place: client-go embeds the per-address "address already in use" text
# inside the "Unable to listen on port" line, and prints that line only when
# every address for the port failed to bind — a partial failure prints neither.
# So a live attempt cannot show both a readiness marker and a bind error, and
# if a future kubectl ever emits both, a forward proven bound must not be
# called fatal.
pf_verdict() {
    local log="$1" port="$2"
    awk -v port="$port" '
        /\[pf-supervisor\].*(starting:|restart #)/ { ready=0; bind_error=0; exited=0; next }
        /port-forward exited/                     { exited=1; next }
        $0 ~ ("Forwarding from (127\\.0\\.0\\.1|\\[::1\\]):" port " ->") { ready=1 }
        /address already in use|Unable to listen on port/                { bind_error=1 }
        END {
            if (ready && !exited)    print "ready"
            else if (bind_error)     print "bind-error"
            else                     print "waiting"
        }' "$log" 2>/dev/null || true
}

# Stop the running kubectl and make sure it is really gone.
#
# SIGTERM alone is not a guarantee: the attempts this is called on are the ones
# already suspected of being wedged, and the caller follows up with an
# unbounded `wait`, so a kubectl that ignores or is too slow to handle the
# signal would hang the supervisor exactly where the deadline was meant to
# rescue it. Escalate after a short grace period.
pf_kill_kubectl() {
    local kpid="$1" _
    kill "$kpid" 2>/dev/null || true
    for _ in $(seq 1 20); do
        kill -0 "$kpid" 2>/dev/null || return 0
        sleep 0.25
    done
    kill -9 "$kpid" 2>/dev/null || true
}

# Wait for the running kubectl to bind, exit, or run out of time.
#
# The restart loop can only react to a kubectl that *exits*. A stalled SPDY
# upgrade to the API server neither binds nor exits, so without a deadline one
# hung attempt pins the forward down for the rest of the job — observed on ROSA
# against a healthy keycloak-0: 32s of complete silence after the banner.
# Recycling the attempt turns that hang into a retry, which is what the
# supervisor is for.
#
# Only lines appended after <marked> count, so a marker from an earlier attempt
# cannot satisfy this one.
pf_await_bind() {
    local log="$1" marked="$2" kpid="$3" stop="$4"
    local deadline=$((SECONDS + PF_BIND_TIMEOUT))
    while kill -0 "$kpid" 2>/dev/null; do
        if tail -n "+$((marked + 1))" "$log" 2>/dev/null | grep -q "Forwarding from"; then
            return 0
        fi
        if [[ -f "$stop" ]]; then
            # Teardown must not block on a kubectl that never exits on its own.
            pf_kill_kubectl "$kpid"
            return 0
        fi
        if [[ "$SECONDS" -ge "$deadline" ]]; then
            echo "[pf-supervisor] $(date -u +%H:%M:%S) no bind within ${PF_BIND_TIMEOUT}s; recycling the attempt" >>"$log"
            pf_kill_kubectl "$kpid"
            return 0
        fi
        sleep 0.5
    done
}

pf_supervise() {
    local ns="$1" target="$2" ports="$3" base="$4"
    local log="${base}.log" pidfile="${base}.pid" stop="${base}.stop"

    # Record our own PID so `stop` can kill this supervisor and its kubectl
    # child as a process group (setsid makes this PID the group lead).
    echo "$$" >"$pidfile"

    # Start each run with a clean log and no stale stop sentinel, so reused
    # (self-hosted) runners don't mix output from previous runs.
    : >"$log"
    rm -f "$stop"

    local restart=0
    while [[ ! -f "$stop" ]]; do
        local marked
        marked=$(wc -l <"$log")
        if [[ "$restart" -gt 0 ]]; then
            echo "[pf-supervisor] $(date -u +%H:%M:%S) restart #${restart}: kubectl port-forward ${target} ${ports} -n ${ns}" >>"$log"
        else
            echo "[pf-supervisor] $(date -u +%H:%M:%S) starting: kubectl port-forward ${target} ${ports} -n ${ns}" >>"$log"
        fi

        kubectl port-forward "$target" "$ports" -n "$ns" </dev/null >>"$log" 2>&1 &
        local kpid=$!
        pf_await_bind "$log" "$marked" "$kpid" "$stop"
        wait "$kpid" 2>/dev/null || true

        # Asked to stop while kubectl was running: exit without restarting.
        [[ -f "$stop" ]] && break

        restart=$((restart + 1))
        echo "[pf-supervisor] $(date -u +%H:%M:%S) port-forward exited; restarting in 1s" >>"$log"
        sleep 1
    done

    echo "[pf-supervisor] $(date -u +%H:%M:%S) stop sentinel found; exiting after ${restart} restart(s)" >>"$log"
}

pf_start() {
    local ns="$1" target="$2" ports="$3" base="$4"

    mkdir -p "$(dirname "$base")"

    # A supervisor left running by an interrupted job on a reused
    # (self-hosted) runner still holds the local port and keeps restarting
    # kubectl. Deleting its metadata alone would orphan it: the replacement
    # overwrites the same .pid, so teardown would kill only the new group and
    # leave the old tunnel serving the previous cluster.
    if [[ -s "${base}.pid" ]]; then
        local stale
        stale=$(cat "${base}.pid")
        if pf_owns "$stale" "$base"; then
            echo "Stopping stale port-forward supervisor for ${base} (pid ${stale})"
            touch "${base}.stop" 2>/dev/null || true
            kill -- "-${stale}" 2>/dev/null || true
            kill "$stale" 2>/dev/null || true
            # kill is asynchronous. If the replacement starts while the old
            # kubectl still holds the port, its first attempt fails to bind
            # and `wait` would call that collision fatal — the recovery
            # defeating itself. Wait for the whole group to go.
            local _
            for _ in $(seq 1 25); do
                kill -0 -- "-${stale}" 2>/dev/null || break
                sleep 0.2
            done
        fi
    fi

    rm -f "${base}.pid" "${base}.stop" "${base}.log"
    setsid nohup bash "$SELF" supervise "$ns" "$target" "$ports" "$base" \
        </dev/null >/dev/null 2>&1 &
    disown || true

    local _
    for _ in $(seq 1 25); do
        [[ -s "${base}.pid" ]] && break
        sleep 0.2
    done
    if [[ ! -s "${base}.pid" ]]; then
        echo "::error::port-forward supervisor for ${base} did not start (no PID written)"
        cat "${base}.log" 2>/dev/null || true
        return 1
    fi
}

# Fail here, with the supervisor log, rather than later inside a test with an
# unexplained connection-refused.
pf_wait() {
    local base="$1" port="$2" attempts="${3:-$PF_WAIT_ATTEMPTS}"
    local log="${base}.log" verdict _
    for _ in $(seq 1 "$attempts"); do
        verdict=$(pf_verdict "$log" "$port")
        case "$verdict" in
            ready)
                echo "✅ port-forward ready on :${port} (${base})"
                return 0
                ;;
            bind-error)
                # Name the cause now instead of waiting out the loop for a
                # generic timeout.
                echo "::error::port-forward could not bind :${port}; the port is held by another process (${base})"
                cat "$log" 2>/dev/null || true
                return 1
                ;;
        esac
        sleep 1
    done
    echo "::error::port-forward never became ready on :${port} (${base})"
    cat "$log" 2>/dev/null || true
    return 1
}

# Tear down every supervisor whose metadata lives in <dir>. Walking the
# directory rather than a caller-supplied list means a forward added to a
# setup step needs no matching edit here, and a supervisor orphaned by an
# earlier job on a reused runner is reclaimed too.
pf_stop() {
    local dir="$1" pidfile base spid
    [[ -d "$dir" ]] || return 0
    for pidfile in "$dir"/*.pid; do
        [[ -e "$pidfile" ]] || continue
        base="${pidfile%.pid}"
        # Drop the stop sentinel first so the supervisor does not restart
        # kubectl after we kill it. Harmless whatever the PID file holds: it
        # is only a file the supervisor polls.
        touch "${base}.stop" 2>/dev/null || true
        [[ -s "$pidfile" ]] || continue
        spid=$(cat "$pidfile")
        if pf_owns "$spid" "$base"; then
            # Kill the whole process group (setsid made the supervisor the
            # group leader) so its kubectl child dies with it.
            kill -- "-${spid}" 2>/dev/null || true
            kill "$spid" 2>/dev/null || true
        fi
    done
}

pf_selftest() {
    local tmp failures=0 stub_path
    tmp=$(mktemp -d)
    # Resolved once: reading $PATH inside each subshell would make shellcheck
    # flag a modification it cannot see escaping (SC2030/SC2031).
    stub_path="$tmp/bin:$PATH"

    # `wait` has no timeout, so poll instead: the point of these cases is that
    # the supervisor exits on its own.
    _wait_with_timeout() {
        local pid="$1" limit="$2" _
        for _ in $(seq 1 $((limit * 4))); do
            kill -0 "$pid" 2>/dev/null || return 0
            sleep 0.25
        done
        return 1
    }

    _expect() {
        if [[ "$2" == "$3" ]]; then
            echo "ok   $1"
        else
            echo "FAIL $1: got '$2' want '$3'"
            failures=$((failures + 1))
        fi
    }

    printf '[pf-supervisor] 00:00:00 starting: x\nUnable to listen on port 9600: bind: address already in use\n' >"$tmp/a.log"
    _expect "failed bind -> bind-error" "$(pf_verdict "$tmp/a.log" 9600)" "bind-error"

    printf '[pf-supervisor] 00:00:00 starting: x\nForwarding from 127.0.0.1:9600 -> 9600\n[pf-supervisor] 00:00:01 port-forward exited; restarting in 1s\n' >"$tmp/a.log"
    _expect "ready then exited -> waiting" "$(pf_verdict "$tmp/a.log" 9600)" "waiting"

    printf '[pf-supervisor] 00:00:00 starting: x\nUnable to listen on port 9600: bind: address already in use\n[pf-supervisor] 00:00:01 restart #1: x\nForwarding from 127.0.0.1:9600 -> 9600\n' >"$tmp/a.log"
    _expect "collision then a bound retry -> ready" "$(pf_verdict "$tmp/a.log" 9600)" "ready"

    printf '[pf-supervisor] 00:00:00 starting: x\nForwarding from [::1]:9600 -> 9600\n' >"$tmp/a.log"
    _expect "IPv6 marker counts -> ready" "$(pf_verdict "$tmp/a.log" 9600)" "ready"

    printf '[pf-supervisor] 00:00:00 starting: x\nForwarding from 127.0.0.1:9200 -> 9200\n' >"$tmp/a.log"
    _expect "another port bound -> waiting" "$(pf_verdict "$tmp/a.log" 9600)" "waiting"

    # A kubectl that never binds and never exits must be recycled, not waited
    # on forever — the failure this deadline exists for.
    mkdir -p "$tmp/bin"
    printf '#!/usr/bin/env bash\nsleep 60\n' >"$tmp/bin/kubectl"
    chmod +x "$tmp/bin/kubectl"
    (
        PATH="$stub_path"
        PF_BIND_TIMEOUT=1
        pf_supervise ns svc/x 1:1 "$tmp/hang"
    ) &
    local sup=$!
    sleep 4
    touch "$tmp/hang.stop"
    wait "$sup" 2>/dev/null || true
    if grep -q "no bind within" "$tmp/hang.log" && grep -q "restart #1" "$tmp/hang.log"; then
        echo "ok   hung attempt is recycled instead of pinning the forward"
    else
        echo "FAIL hung attempt is recycled: log did not show a recycle and a restart"
        cat "$tmp/hang.log"
        failures=$((failures + 1))
    fi

    # A kubectl that ignores SIGTERM must still be reaped, or the unbounded
    # `wait` after the deadline would hang the supervisor anyway.
    mkdir -p "$tmp/bin"
    printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 60\n' >"$tmp/bin/kubectl"
    chmod +x "$tmp/bin/kubectl"
    (
        PATH="$stub_path"
        PF_BIND_TIMEOUT=1
        pf_supervise ns svc/x 1:1 "$tmp/stubborn"
    ) &
    local stubborn=$!
    sleep 5
    touch "$tmp/stubborn.stop"
    if _wait_with_timeout "$stubborn" 12; then
        echo "ok   a kubectl ignoring SIGTERM is escalated to SIGKILL"
    else
        echo "FAIL a kubectl ignoring SIGTERM wedged the supervisor"
        kill -9 "$stubborn" 2>/dev/null || true
        failures=$((failures + 1))
    fi

    # A PID that is not our supervisor must never be signalled.
    sleep 30 &
    local victim=$!
    echo "$victim" >"$tmp/zeebe.pid"
    pf_stop "$tmp"
    sleep 0.3
    if kill -0 "$victim" 2>/dev/null; then
        echo "ok   foreign pid survives stop"
    else
        echo "FAIL foreign pid survives stop: it was signalled"
        failures=$((failures + 1))
    fi
    kill "$victim" 2>/dev/null || true
    wait "$victim" 2>/dev/null || true

    pf_stop "$tmp/does-not-exist"
    _expect "stop on a missing dir -> 0" "$?" "0"

    rm -rf "$tmp"
    return "$failures"
}

main() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        start)
            [[ "$#" -eq 4 ]] || { echo "usage: port-forward.sh start <namespace> <target> <ports> <base>" >&2; return 2; }
            pf_start "$@"
            ;;
        wait)
            [[ "$#" -ge 2 ]] || { echo "usage: port-forward.sh wait <base> <local-port> [attempts]" >&2; return 2; }
            pf_wait "$@"
            ;;
        stop)
            [[ "$#" -eq 1 ]] || { echo "usage: port-forward.sh stop <dir>" >&2; return 2; }
            pf_stop "$@"
            ;;
        supervise)
            [[ "$#" -eq 4 ]] || { echo "usage: port-forward.sh supervise <namespace> <target> <ports> <base>" >&2; return 2; }
            pf_supervise "$@"
            ;;
        selftest)
            pf_selftest
            ;;
        *)
            echo "usage: port-forward.sh start|wait|stop|supervise|selftest ..." >&2
            return 2
            ;;
    esac
}

main "$@"
