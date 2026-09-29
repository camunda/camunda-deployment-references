#!/bin/sh
# Dump the series scraped since the previous cycle into OUTBOX, where the
# upload sidecar picks them up. Runs in the background of the Prometheus
# container, which is the only one holding the TSDB and promtool.
#
# Output is the Prometheus text format with millisecond timestamps, which
# `promtool push metrics` replays over remote write on the receiving side.
# shellcheck disable=SC3040 # busybox ash, the image's shell, supports pipefail
set -o pipefail

OUTBOX="${OUTBOX:-/outbox}"
INTERVAL="${EXPORT_INTERVAL_SECONDS:-300}"
DB_PATH="${DB_PATH:-/prometheus/data}"
WORK=/tmp/export
mkdir -p "$WORK"

LAST=0
while true; do
    sleep "$INTERVAL"

    # Leave the last minute out: it may still be appended to.
    MAX=$(( $(date +%s) * 1000 - 60000 ))
    FILE="${WORK}/${MAX}.prom.gz"

    if promtool tsdb dump-openmetrics --sandbox-dir-root="$WORK" \
        --min-time=$(( LAST + 1 )) --max-time="$MAX" "$DB_PATH" |
        awk '/^#/ { next } { i = match($0, / [^ ]+$/); printf "%s %.0f\n", substr($0, 1, i - 1), substr($0, i + 1) * 1000 }' |
        gzip -c > "$FILE"; then
        LAST="$MAX"
        if [ -n "$(gunzip -c "$FILE" | head -c 1)" ]; then
            mv "$FILE" "${OUTBOX}/"
            echo "exported series up to ${MAX}"
        else
            rm -f "$FILE"
        fi
    else
        rm -f "$FILE"
        echo "dump failed, retrying next cycle with the same window"
    fi
done
