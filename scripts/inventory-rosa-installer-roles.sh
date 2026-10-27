#!/usr/bin/env bash

set -euo pipefail

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

installer_role_name() {
  local role_arn="$1"
  [[ "$role_arn" == */* ]] || return 0
  printf '%s\n' "${role_arn##*/}"
}

trust_status() {
  jq -r '
    [(.Role.AssumeRolePolicyDocument.Statement | if type == "array" then . else [.] end)[]?
      | select(.Effect == "Allow")
      | (.Action | if type == "array" then . else [.] end) as $actions
      | (.Principal.AWS? | if type == "array" then . else [.] end) as $principals
      | select(any($actions[]; . == "sts:AssumeRole"))
      | select(any($principals[]; . == "arn:aws:iam::710019948333:role/RH-Managed-OpenShift-Installer"))]
    | if length > 0 then "ok" else "broken" end'
}

hcp_clusters() {
  jq -c '[.[] | select(.hypershift.enabled == true)]'
}

has_role_arn() {
  local role_arn="$1"
  jq -e --arg role_arn "$role_arn" 'index($role_arn) != null' >/dev/null
}

selftest() {
  local valid broken wrong_account clusters role_arns tmp out rc failures=0
  valid='{"Role":{"AssumeRolePolicyDocument":{"Statement":{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::710019948333:role/RH-Managed-OpenShift-Installer"}}}}}'
  broken='{"Role":{"AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::000000000000:role/Other"}}]}}}'
  wrong_account='{"Role":{"AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::000000000000:role/RH-Managed-OpenShift-Installer"}}]}}}'
  clusters='[{"name":"hcp","hypershift":{"enabled":true}},{"name":"classic","hypershift":{"enabled":false}}]'
  role_arns='["arn:aws:iam::000000000000:role/example-account-HCP-ROSA-Installer-Role"]'

  [[ "$(installer_role_name 'arn:aws:iam::000000000000:role/example-account-HCP-ROSA-Installer-Role')" == "example-account-HCP-ROSA-Installer-Role" ]] || failures=$((failures + 1))
  [[ -z "$(installer_role_name '')" ]] || failures=$((failures + 1))
  [[ "$(trust_status <<<"$valid")" == "ok" ]] || failures=$((failures + 1))
  [[ "$(trust_status <<<"$broken")" == "broken" ]] || failures=$((failures + 1))
  [[ "$(trust_status <<<"$wrong_account")" == "broken" ]] || failures=$((failures + 1))
  [[ "$(hcp_clusters <<<"$clusters")" == '[{"name":"hcp","hypershift":{"enabled":true}}]' ]] || failures=$((failures + 1))
  has_role_arn 'arn:aws:iam::000000000000:role/example-account-HCP-ROSA-Installer-Role' <<<"$role_arns" || failures=$((failures + 1))
  ! has_role_arn 'arn:aws:iam::111111111111:role/example-account-HCP-ROSA-Installer-Role' <<<"$role_arns" || failures=$((failures + 1))

  mkdir -p "$(dirname "$SELF")/../debug"
  tmp=$(mktemp -d "$(dirname "$SELF")/../debug/inventory-rosa.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  mkdir "$tmp/bin"

  cat >"$tmp/bin/rosa" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
[{"name":"healthy","hypershift":{"enabled":true},"status":{"state":"ready"},"aws":{"sts":{"role_arn":"arn:aws:iam::000000000000:role/healthy-account-HCP-ROSA-Installer-Role"}}},
 {"name":"missing","hypershift":{"enabled":true},"status":{"state":"error"}},
 {"name":"unreadable","hypershift":{"enabled":true},"status":{"state":"error"},"aws":{"sts":{"role_arn":"arn:aws:iam::000000000000:role/unreadable-account-HCP-ROSA-Installer-Role"}}},
 {"name":"classic","hypershift":{"enabled":false},"status":{"state":"ready"}}]
JSON
STUB
  cat >"$tmp/bin/aws" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "iam list-roles --query Roles[].Arn --output json")
    cat <<'JSON'
["arn:aws:iam::000000000000:role/healthy-account-HCP-ROSA-Installer-Role",
 "arn:aws:iam::000000000000:role/unreadable-account-HCP-ROSA-Installer-Role",
 "arn:aws:iam::000000000000:role/orphan-account-HCP-ROSA-Installer-Role"]
JSON
    ;;
  *"get-role --role-name healthy-account-HCP-ROSA-Installer-Role"*)
    echo '{"Role":{"AssumeRolePolicyDocument":{"Statement":{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::710019948333:role/RH-Managed-OpenShift-Installer"}}}}}'
    ;;
  *"get-role --role-name unreadable-account-HCP-ROSA-Installer-Role"*)
    echo "AccessDenied" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$tmp/bin/rosa" "$tmp/bin/aws"

  rc=0
  out=$(PATH="$tmp/bin:$PATH" bash "$SELF" 2>&1) || rc=$?
  [[ "$rc" == 1 ]] || failures=$((failures + 1))
  grep -Eq '^healthy[[:space:]]+ready[[:space:]]+ok[[:space:]]*$' <<<"$out" || failures=$((failures + 1))
  grep -Eq '^missing[[:space:]]+error[[:space:]]+missing[[:space:]]*$' <<<"$out" || failures=$((failures + 1))
  grep -Eq '^unreadable[[:space:]]+error[[:space:]]+unreadable[[:space:]]*$' <<<"$out" || failures=$((failures + 1))
  grep -q '^  orphan-account-HCP-ROSA-Installer-Role$' <<<"$out" || failures=$((failures + 1))
  grep -q '^FAIL: found 3 missing, unreadable, broken-trust, or orphan installer role(s).$' <<<"$out" || failures=$((failures + 1))
  ! grep -q '^classic ' <<<"$out" || failures=$((failures + 1))

  if ((failures)); then
    echo "FAIL: ${failures} inventory self-test(s) failed" >&2
    return 1
  fi
  echo "PASS: ROSA installer-role inventory self-test"
}

if [[ "${1:-}" == "selftest" ]]; then
  selftest
  exit
fi

for command in aws jq rosa; do
  command -v "$command" >/dev/null || {
    echo "Error: required command not found: $command" >&2
    exit 1
  }
done

clusters=$(rosa list cluster --output json | hcp_clusters)
role_arns=$(aws iam list-roles --query 'Roles[].Arn' --output json)
findings=0

printf '%-40s %-16s %-16s\n' CLUSTER STATE INSTALLER_ROLE
while IFS= read -r cluster; do
  name=$(jq -r '.name' <<<"$cluster")
  state=$(jq -r '.status.state // "unknown"' <<<"$cluster")
  role_arn=$(jq -r '.aws.sts.role_arn // ""' <<<"$cluster")
  role_name=$(installer_role_name "$role_arn")

  if [[ -z "$role_arn" ]] || ! has_role_arn "$role_arn" <<<"$role_arns"; then
    status=missing
    findings=$((findings + 1))
  elif role=$(aws iam get-role --role-name "$role_name" --output json); then
    status=$(trust_status <<<"$role")
    [[ "$status" == "ok" ]] || findings=$((findings + 1))
  else
    status=unreadable
    findings=$((findings + 1))
  fi

  printf '%-40s %-16s %-16s\n' "$name" "$state" "$status"
done < <(jq -c '.[]' <<<"$clusters")

cluster_role_arns=$(jq -r '.[].aws.sts.role_arn // empty' <<<"$clusters")
orphans=$(jq -r '.[] | select(endswith("-account-HCP-ROSA-Installer-Role"))' <<<"$role_arns" |
  while IFS= read -r role_arn; do
    grep -qxF "$role_arn" <<<"$cluster_role_arns" || installer_role_name "$role_arn"
  done)

if [[ -n "$orphans" ]]; then
  echo
  echo "Installer roles without a ROSA cluster:"
  while IFS= read -r role_name; do
    printf '  %s\n' "$role_name"
    findings=$((findings + 1))
  done <<<"$orphans"
fi

if ((findings)); then
  echo
  echo "FAIL: found ${findings} missing, unreadable, broken-trust, or orphan installer role(s)." >&2
  echo "See https://github.com/camunda/camunda-deployment-references/issues/3122 for recovery context." >&2
  exit 1
fi

echo
echo "PASS: every ROSA cluster has a readable installer role with the expected trust, and no installer roles are orphaned."
