#!/usr/bin/env bash

set -euo pipefail

installer_role_name() {
  local role_arn="$1"
  [[ "$role_arn" == */* ]] && printf '%s\n' "${role_arn##*/}"
}

trust_status() {
  jq -r '
    [.Role.AssumeRolePolicyDocument.Statement[]?
      | select(.Effect == "Allow")
      | (.Action | if type == "array" then . else [.] end) as $actions
      | (.Principal.AWS? | if type == "array" then . else [.] end) as $principals
      | select(any($actions[]; . == "sts:AssumeRole"))
      | select(any($principals[]; type == "string" and endswith(":role/RH-Managed-OpenShift-Installer")))]
    | if length > 0 then "ok" else "broken" end'
}

selftest() {
  local valid broken failures=0
  valid='{"Role":{"AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::000000000000:role/RH-Managed-OpenShift-Installer"}}]}}}'
  broken='{"Role":{"AssumeRolePolicyDocument":{"Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"arn:aws:iam::000000000000:role/Other"}}]}}}'

  [[ "$(installer_role_name 'arn:aws:iam::000000000000:role/example-account-HCP-ROSA-Installer-Role')" == "example-account-HCP-ROSA-Installer-Role" ]] || failures=$((failures + 1))
  [[ "$(trust_status <<<"$valid")" == "ok" ]] || failures=$((failures + 1))
  [[ "$(trust_status <<<"$broken")" == "broken" ]] || failures=$((failures + 1))

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

clusters=$(rosa list cluster --output json)
role_names=$(aws iam list-roles --query 'Roles[].RoleName' --output json)
findings=0

printf '%-40s %-16s %-16s\n' CLUSTER STATE INSTALLER_ROLE
while IFS= read -r cluster; do
  name=$(jq -r '.name' <<<"$cluster")
  state=$(jq -r '.status.state // "unknown"' <<<"$cluster")
  role_name=$(installer_role_name "$(jq -r '.aws.sts.role_arn // ""' <<<"$cluster")")

  if [[ -z "$role_name" ]] || ! jq -e --arg role "$role_name" 'index($role) != null' >/dev/null <<<"$role_names"; then
    status=missing
    findings=$((findings + 1))
  elif role=$(aws iam get-role --role-name "$role_name" --output json 2>&1); then
    status=$(trust_status <<<"$role")
    [[ "$status" == "ok" ]] || findings=$((findings + 1))
  else
    status=unreadable
    findings=$((findings + 1))
  fi

  printf '%-40s %-16s %-16s\n' "$name" "$state" "$status"
done < <(jq -c '.[]' <<<"$clusters")

cluster_roles=$(jq -r '.[].aws.sts.role_arn // empty | split("/")[-1]' <<<"$clusters")
orphans=$(jq -r '.[] | select(endswith("-account-HCP-ROSA-Installer-Role"))' <<<"$role_names" |
  while IFS= read -r role_name; do
    grep -qxF "$role_name" <<<"$cluster_roles" || printf '%s\n' "$role_name"
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
