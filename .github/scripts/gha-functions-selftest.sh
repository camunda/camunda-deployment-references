#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/generate.sh" <<'EOF'
SELFTEST_CLIENT_SECRET="selftest-secret-value"
SELFTEST_ADMIN_PASSWORD="selftest-password-value"
SELFTEST_EMPTY_SECRET=""
SELFTEST_PLAIN="selftest-plain-value"
EOF

# shellcheck source=/dev/null
source "$here/gha-functions.sh"

export GITHUB_ENV="$work/github_env"
: >"$GITHUB_ENV"
output=$(export_new_env_vars "$work/generate.sh")

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

grep -qxF "::add-mask::selftest-secret-value" <<<"$output" || fail "SECRET value is not masked"
grep -qxF "::add-mask::selftest-password-value" <<<"$output" || fail "PASSWORD value is not masked"
masks=$(grep -c '^::add-mask::' <<<"$output" || true)
[[ "$masks" -eq 2 ]] || fail "expected 2 mask commands, got $masks"

for line in SELFTEST_CLIENT_SECRET=selftest-secret-value SELFTEST_ADMIN_PASSWORD=selftest-password-value SELFTEST_EMPTY_SECRET= SELFTEST_PLAIN=selftest-plain-value; do
    grep -qxF "$line" "$GITHUB_ENV" || fail "$line is not exported"
done

echo "gha-functions self-test passed"
