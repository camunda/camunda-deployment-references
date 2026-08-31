#!/bin/bash
set -euo pipefail

# Measures, from every active region, the latency of a write to the single
# Aurora writer.
#
#   ./measure-rdbms-latency.sh
#
# WHY THIS EXISTS
#
# The Zeebe data plane is active-active, but the database tier is
# active-standby: every broker exports to one writer. Brokers that are not
# co-located with it pay the inter-region round trip on every export flush, and
# that cost is the main sizing input for
# `orchestration.data.secondaryStorage.rdbms.queueSize`. The README states this
# as a caveat; this procedure turns it into a number.
#
# Two measurements per region, because they fail differently:
#
#   round trip    — `SELECT 1`. Close to the network RTT to the writer, and the
#                   floor for anything the exporter does.
#   durable write — an insert and its commit. Adds the writer's durability path
#                   on top of the round trip.
#
# Both use a scratch table created and dropped by this procedure. Nothing in the
# Camunda schema is read or written, so it is safe against a live cluster.
#
# A region that cannot be measured is reported and skipped rather than failing
# the run: this is a diagnostic, and it must not mask the result of whatever
# called it.

: "${CLUSTER_CONTEXTS:?CLUSTER_CONTEXTS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_ACTIVE_REGIONS:?CAMUNDA_ACTIVE_REGIONS must be set, source export_environment_prerequisites.sh}"
: "${SUBMARINER_CLUSTER_IDS:?SUBMARINER_CLUSTER_IDS must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_NAMESPACE:?CAMUNDA_NAMESPACE must be set, source export_environment_prerequisites.sh}"
: "${CAMUNDA_RDBMS_URL:?CAMUNDA_RDBMS_URL must be set, source export-terraform-outputs.sh}"
: "${CAMUNDA_RDBMS_USERNAME:?CAMUNDA_RDBMS_USERNAME must be set, source export_environment_prerequisites.sh}"

# renovate: datasource=docker depName=postgres versioning=docker
PSQL_IMAGE="${PSQL_IMAGE:-postgres:17-alpine}"

SAMPLES="${RDBMS_LATENCY_SAMPLES:-20}"
PROBE_TIMEOUT="${RDBMS_LATENCY_TIMEOUT:-300s}"
PROBE_TABLE="${RDBMS_LATENCY_TABLE:-camunda_rdbms_latency_probe}"
PROBE_POD="rdbms-latency-probe"

read -r -a contexts <<<"$CLUSTER_CONTEXTS"
read -r -a cluster_ids <<<"$SUBMARINER_CLUSTER_IDS"

###############################################################################
# The JDBC URL is the only place the endpoint is defined, so it is parsed here #
# rather than adding a second source of truth. Shape:                          #
#   jdbc:aws-wrapper:postgresql://<host>:<port>/<db>?<params>                  #
###############################################################################

_authority="${CAMUNDA_RDBMS_URL#*://}"
_hostport="${_authority%%/*}"
DB_HOST="${_hostport%%:*}"
DB_PORT="${_hostport##*:}"
[ "$DB_PORT" = "$DB_HOST" ] && DB_PORT=5432
_path="${_authority#*/}"
DB_NAME="${_path%%\?*}"

if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ "$DB_HOST" = "$CAMUNDA_RDBMS_URL" ]; then
    echo "ERROR: cannot parse host and database out of CAMUNDA_RDBMS_URL." >&2
    echo "       Got host='$DB_HOST' port='$DB_PORT' db='$DB_NAME'." >&2
    exit 1
fi

echo "Writer endpoint : $DB_HOST:$DB_PORT/$DB_NAME"
echo "Samples         : $SAMPLES per measurement"
echo

cleanup() {
    for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
        kubectl --context "${contexts[$i]}" -n "$CAMUNDA_NAMESPACE" \
            delete pod "$PROBE_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# The median is reported rather than the mean: one scheduling hiccup or TCP
# retransmit skews a mean of twenty samples enough to be misread as a topology
# problem.
#
# psql's own `\timing` provides the measurement. Timing the client process
# instead was tried and reports 0 ms: the probe image is Alpine, whose busybox
# `date` does not implement `%N`. Running every sample in one session also
# keeps process startup and connection setup out of the number, which is what
# makes it comparable between regions.
probe_command() {
    cat <<EOF
set -eu
export PGPASSWORD="\$RDBMS_PASSWORD"
PSQL="psql -h $DB_HOST -p $DB_PORT -U $CAMUNDA_RDBMS_USERNAME -d $DB_NAME -tAX -v ON_ERROR_STOP=1"

\$PSQL -c 'CREATE TABLE IF NOT EXISTS $PROBE_TABLE (id bigserial primary key, at timestamptz default now())' >/dev/null

median() {
  # printf, not echo: the probe image runs busybox, whose echo may expand the
  # backslash in \timing depending on how it was built.
  {
    printf '%s\n' '\timing on'
    i=0
    while [ \$i -lt $SAMPLES ]; do
      printf '%s;\n' "\$1"
      i=\$((i + 1))
    done
  } >/tmp/probe.sql

  # "Time: 7.123 ms" -> 7.123
  \$PSQL -f /tmp/probe.sql |
    awk '/^Time:/ {print \$2}' |
    sort -n |
    awk '{a[NR]=\$1} END {if (NR) printf "%.1f", a[int((NR+1)/2)]}'
}

select_ms=\$(median 'SELECT 1')
commit_ms=\$(median 'INSERT INTO $PROBE_TABLE DEFAULT VALUES')

# Self-cleaning, so no region depends on another one having run.
\$PSQL -c 'DROP TABLE IF EXISTS $PROBE_TABLE' >/dev/null

echo "RESULT \$select_ms \$commit_ms"
EOF
}

failures=0
results=""

for ((i = 0; i < CAMUNDA_ACTIVE_REGIONS; i++)); do
    context="${contexts[$i]}"
    region_id="${cluster_ids[$i]}"

    echo "--> Measuring from $region_id ($context)"

    # The probe reads the password from the secret create-rdbms-secret.sh
    # installs. Without it the pod never starts and the wait below burns its
    # whole budget, which is pure noise on a run that failed before Camunda was
    # ever deployed.
    if ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        get secret camunda-rdbms-secret >/dev/null 2>&1; then
        echo "    no camunda-rdbms-secret in $context/$CAMUNDA_NAMESPACE, skipping"
        continue
    fi

    kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" \
        delete pod "$PROBE_POD" --ignore-not-found >/dev/null 2>&1 || true

    # The password comes from the secret create-rdbms-secret.sh already
    # installed, never from the command line: a pod spec is readable by anyone
    # with get pod, and this architecture keeps the password out of everything
    # but the secret.
    if ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${PROBE_POD}
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  containers:
    - name: psql
      image: ${PSQL_IMAGE}
      env:
        - name: RDBMS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: camunda-rdbms-secret
              key: password
      command: ["sh", "-c"]
      args:
        - |
$(probe_command | sed 's/^/          /')
EOF
    then
        echo "    could not create the probe pod, continuing"
        failures=$((failures + 1))
        continue
    fi

    if ! kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" wait \
        --for=jsonpath='{.status.phase}'=Succeeded "pod/$PROBE_POD" \
        --timeout="$PROBE_TIMEOUT" >/dev/null 2>&1; then
        echo "    the probe did not succeed within $PROBE_TIMEOUT, continuing:"
        kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" logs "$PROBE_POD" 2>&1 |
            tail -20 | sed 's/^/      /'
        failures=$((failures + 1))
        continue
    fi

    output="$(kubectl --context "$context" -n "$CAMUNDA_NAMESPACE" logs "$PROBE_POD" 2>&1)"
    read -r _ select_ms commit_ms <<<"$(echo "$output" | awk '/^RESULT/ {print; exit}')"

    if [ -z "${select_ms:-}" ] || [ -z "${commit_ms:-}" ]; then
        echo "    unparseable probe output, continuing:"
        echo "$output" | tail -20 | sed 's/^/      /'
        failures=$((failures + 1))
        continue
    fi

    echo "    round trip ${select_ms}ms, durable write ${commit_ms}ms (median of $SAMPLES)"
    results="${results}${region_id}|${select_ms}|${commit_ms}"$'\n'
done

echo
echo "RDBMS write latency to the single writer, per region"
echo "  region             round trip   durable write"
printf '%s' "$results" | while IFS='|' read -r region select_ms commit_ms; do
    [ -n "$region" ] || continue
    printf '  %-17s %8sms %13sms\n' "$region" "$select_ms" "$commit_ms"
done

echo
echo "The region hosting the writer is the baseline. Every other region pays the"
echo "difference on every export flush, which is the number to size"
echo "orchestration.data.secondaryStorage.rdbms.queueSize against."

if [ "$failures" -ne 0 ]; then
    echo
    echo "WARNING: $failures region(s) could not be measured." >&2
fi
