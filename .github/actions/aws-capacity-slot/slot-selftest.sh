#!/usr/bin/env bash
# Offline self-test of slot.sh. A fake `aws` keeps S3 objects in a directory and
# answers usage and quota lookups from FAKE_USAGE / FAKE_QUOTA.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/s3"

cat >"$work/bin/aws" <<'EOF'
#!/usr/bin/env bash
# Usage: aws <service> <op> [args...]
svc=$1 op=$2
shift 2
key='' body='' out='' ifnone='' ifmatch='' prefix=''
while (($#)); do
    case "$1" in
    --key) key=$2; shift ;;
    --body) body=$2; shift ;;
    --if-none-match) ifnone=$2; shift ;;
    --if-match) ifmatch=$2; shift ;;
    --prefix) prefix=$2; shift ;;
    --region | --bucket | --query | --output | --filters | --service-code | --quota-code) shift ;;
    --no-cli-pager) ;;
    *) out=$1 ;;
    esac
    shift
done
f="$FAKE_S3/$(printf '%s' "$key" | tr / _)"
etag() { md5sum "$f" 2>/dev/null | cut -c1-8 || md5 -q "$f" | cut -c1-8; }
case "$svc $op" in
"s3api put-object")
    if [[ -n "$ifnone" && -e "$f" ]]; then echo PreconditionFailed >&2; exit 1; fi
    if [[ -n "$ifmatch" && "$(etag)" != "$ifmatch" ]]; then echo PreconditionFailed >&2; exit 1; fi
    cp "$body" "$f"; printf '%s\n' "$key" >"$f.key" ;;
"s3api get-object")
    [[ -e "$f" ]] || { echo NoSuchKey >&2; exit 1; }
    cp "$f" "$out"; etag ;;
"s3api delete-object")
    [[ -z "$ifmatch" || "$(etag)" == "$ifmatch" ]] || { echo PreconditionFailed >&2; exit 1; }
    rm -f "$f" "$f.key" ;;
"s3api list-objects-v2")
    [[ -z "${FAKE_LIST_FAIL:-}" ]] || { echo AccessDenied >&2; exit 1; }
    cat "$FAKE_S3"/*.key 2>/dev/null | jq -R -s --arg p "$prefix" 'split("\n") | map(select(. != "" and startswith($p)))' ||
        echo '[]' ;;
"service-quotas get-service-quota") echo "$FAKE_QUOTA" ;;
*) echo "$FAKE_USAGE" ;;
esac
EOF
chmod +x "$work/bin/aws"

export PATH="$work/bin:$PATH" FAKE_S3="$work/s3" BUCKET=b BUCKET_REGION=r
export SLOTS=3 LEASE_MINUTES=60 WAIT_MINUTES=0 POLL_SECONDS=1 PROVISION_MINUTES=45 MARGIN=0
failures=0
_expect() {
    if [[ "$2" == "$3" ]]; then echo "ok   $1"; else
        echo "FAIL $1: got '$2' want '$3'"
        failures=$((failures + 1))
    fi
}
slots_of() {
    local f n=0
    for f in "$FAKE_S3"/ci-locks_"$1"_slot-[0-9]; do [[ -e "$f" ]] && n=$((n + 1)); done
    echo "$n"
}
run() { "$here/slot.sh" acquire >/dev/null 2>&1 && echo acquired || echo refused; }

# Quota 10, usage 0. Suite A reserves 6 RDS clusters in eu-west-2.
export FAKE_USAGE=0 FAKE_QUOTA=10
_expect "first run of a suite is admitted" \
    "$(POOL=a OWNER=run-a REGIONS=eu-west-2 NEEDS=$'rds-clusters=6' run)" acquired
_expect "slot body records regions and needs" \
    "$(jq -c '{regions, needs}' "$FAKE_S3"/ci-locks_a_slot-0)" '{"regions":["eu-west-2"],"needs":{"rds-clusters":6}}'
_expect "another suite sees the first suite's reservation" \
    "$(POOL=b OWNER=run-b REGIONS=eu-west-2 NEEDS=$'rds-clusters=6' run)" refused
_expect "a reservation in another region does not count" \
    "$(POOL=b OWNER=run-b REGIONS=eu-west-3 NEEDS=$'rds-clusters=6' run)" acquired
_expect "another resource of the same region does not count" \
    "$(POOL=c OWNER=run-c REGIONS=eu-west-2 NEEDS=$'vpcs=6' run)" acquired
_expect "two legs of one job hold two slots" \
    "$(POOL=d OWNER=run-d/leg1 REGIONS='' NEEDS='' run; POOL=d OWNER=run-d/leg2 REGIONS='' NEEDS='' run; slots_of d)" $'acquired\nacquired\n2'
_expect "unknown resource fails" \
    "$(POOL=e OWNER=run-e REGIONS=eu-west-2 NEEDS=$'nope=1' "$here/slot.sh" acquire >/dev/null 2>&1; echo $?)" 2
_expect "a later job releases by owner, without the slot key or the pool size" \
    "$(POOL=d SLOTS=1 OWNER=run-d/leg2 SLOT_KEY='' "$here/slot.sh" release >/dev/null 2>&1; slots_of d)" 1
_expect "release by owner leaves other legs alone" \
    "$(jq -r .owner "$FAKE_S3"/ci-locks_d_slot-0)" run-d/leg1
_expect "a rerun of the same leg renews its slot" \
    "$(POOL=d OWNER=run-d/leg1 REGIONS='' NEEDS='' run; slots_of d)" $'acquired\n1'

_expect "a failed listing refuses admission" \
    "$(FAKE_LIST_FAIL=1 POOL=f OWNER=run-f REGIONS=eu-west-2 NEEDS=$'vpcs=1' run)" refused
_expect "a failed listing fails release by owner" \
    "$(FAKE_LIST_FAIL=1 POOL=d OWNER=run-d/leg1 SLOT_KEY='' "$here/slot.sh" release >/dev/null 2>&1; echo $?)" 1

# Quota 10 in eu-west-1. Run g is admitted at usage 2 and reserves 4 EIPs.
_expect "an admitted run records the usage it saw" \
    "$(FAKE_USAGE=2 POOL=g OWNER=run-g REGIONS=eu-west-1 NEEDS=$'elastic-ips=4' run; jq -c .base "$FAKE_S3"/ci-locks_g_slot-0)" \
    $'acquired\n{"eu-west-1":{"elastic-ips":2}}'
_expect "before run g creates anything, its 4 still count (2+4+5 > 10)" \
    "$(FAKE_USAGE=2 POOL=h OWNER=run-h REGIONS=eu-west-1 NEEDS=$'elastic-ips=5' run)" refused
_expect "once run g created its 4, they do not count twice (6+0+4 = 10)" \
    "$(FAKE_USAGE=6 POOL=h OWNER=run-h REGIONS=eu-west-1 NEEDS=$'elastic-ips=4' run)" acquired
POOL=h OWNER=run-h SLOT_KEY='' "$here/slot.sh" release >/dev/null 2>&1
_expect "deletions since admission keep the full reservation (1+4+6 > 10)" \
    "$(FAKE_USAGE=1 POOL=h OWNER=run-h REGIONS=eu-west-1 NEEDS=$'elastic-ips=6' run)" refused
jq 'del(.base)' "$FAKE_S3"/ci-locks_g_slot-0 >"$work/old" && cp "$work/old" "$FAKE_S3"/ci-locks_g_slot-0
_expect "a slot without a recorded usage keeps its full reservation (6+4+1 > 10)" \
    "$(FAKE_USAGE=6 POOL=h OWNER=run-h REGIONS=eu-west-1 NEEDS=$'elastic-ips=1' run)" refused

echo "${failures} failure(s)"
[[ "$failures" -eq 0 ]]
