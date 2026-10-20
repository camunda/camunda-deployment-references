# shellcheck shell=bash disable=SC2034,SC2317  # sourced: destroy-resources.sh reads these variables and calls these fakes
# Sourced by `destroy-resources.sh selftest`, never run on its own: it calls
# the functions and reads the variables that script defines.

# destroy_selftest checks classify_destroy_error against the verbatim error text
# each case was written for, and that every handler it can name exists.
#
# The classifier is a lookup table matched against vendor error strings, which
# is exactly the kind of thing that rots silently: a pattern typo, or a handler
# renamed without its case, would simply stop recovering and the daily cleanup
# would go back to leaking with no signal.
destroy_selftest() {
  local failures=0 got

  _expect() {
    if [[ "$2" == "$3" ]]; then
      echo "ok   $1"
    else
      echo "FAIL $1: got '$2' want '$3'"
      failures=$((failures + 1))
    fi
  }

  # Verbatim from the runs each case was written for.
  local dep_violation="Error: deleting EC2 VPC (vpc-EXAMPLE): operation error EC2: DeleteVpc, api error DependencyViolation: The vpc has dependencies and cannot be deleted."
  local oidc_in_use="Error: there are clusters using OIDC config 'EXAMPLEOIDCCONFIGID', can't delete the OIDC config"
  local trust_policy="status is 400, code is 'CLUSTERS-MGMT-400' ... Failed to delete cluster: Please make sure IAM role 'arn:aws:iam::000000000000:role/EXAMPLE-account-HCP-ROSA-Installer-Role' exists, and add it to the trust policy"
  local gone="Error: status is 404, identifier is '404', code is 'CLUSTERS-MGMT-404'"
  local delete_conflict="Error: deleting IAM Policy (arn:aws:iam::000000000000:policy/EXAMPLE-external-dns-policy): DeleteConflict: Cannot delete a policy attached to entities."
  local s3_scanner="Error: emptying S3 Bucket (eks-dual-36687d47d-7ce10-elastic-backup): listing S3 bucket (...) object versions: operation error S3: ListObjectVersions, https response error StatusCode: 200, RequestID: 8YBJSRFA8EBDPG48, ... decomposing response: bufio.Scanner: token too long"
  local unknown="Error: Invalid provider configuration"
  local last_master="Error: deleting RDS Cluster Instance (ecsdr-1234-r1-camunda-db-0): operation error RDS: DeleteDBInstance, https response error StatusCode: 400, api error InvalidDBClusterStateFault: Cannot delete the last instance of the master cluster. Delete the replica cluster before deleting the last master cluster instance."
  # Verbatim from the 2026-10-18 lifecycle-lane teardown.
  local stale_eip="Error: deleting EC2 EIP (eipalloc-05ae99ac0dafa1cf0): operation error EC2: ReleaseAddress, https response error StatusCode: 400, RequestID: 83d85ba5-6003-4c96-95c1-0385e79bf643, api error InvalidNetworkInterfaceID.NotFound: The networkInterface ID 'eni-060ceab86cbd3dd50' does not exist"
  local global_state="Error: deleting RDS Global Cluster (ecsdr-1234-global-db): operation error RDS: DeleteGlobalCluster, https response error StatusCode: 400, api error InvalidGlobalClusterStateFault: Global Cluster ecsdr-1234-global-db is not empty"

  _expect "S3 version listing scanner failure -> empty bucket" \
    "$(classify_destroy_error "$s3_scanner" clusters)" "remediate_s3_versions"
  _expect "S3 bucket name extracted from destroy error" \
    "$(extract_s3_bucket_names "$s3_scanner")" "eks-dual-36687d47d-7ce10-elastic-backup"
  _expect "unrelated scanner failure has no handler" \
    "$(classify_destroy_error 'Error: reading IAM Policy: bufio.Scanner: token too long' clusters)" ""
  local invalid_bucket
  for invalid_bucket in 'bad;command' 'bad/name' 'UPPERCASE' '-bad' 'bad-' 'a..b' 'ab' '192.168.0.1'; do
    _expect "reject invalid bucket $invalid_bucket" \
      "$(extract_s3_bucket_names "${s3_scanner/eks-dual-36687d47d-7ce10-elastic-backup/$invalid_bucket}")" ""
  done
  _expect "unrelated bucket error is not extracted" \
    "$(extract_s3_bucket_names 'Error: emptying S3 Bucket (unrelated-bucket): AccessDenied')" ""
  _expect "multiple failed buckets are deduplicated" \
    "$(extract_s3_bucket_names "$s3_scanner"$'\n\n'"$s3_scanner")" "eks-dual-36687d47d-7ce10-elastic-backup"
  _expect "another error block cannot supply the scanner failure" \
    "$(extract_s3_bucket_names 'Error: emptying S3 Bucket (unrelated-bucket): AccessDenied
Error: ListObjectVersions: bufio.Scanner: token too long')" ""

  # The subshell's aws function intercepts every call; no cloud access is possible.
  if (
    test_dir=$(mktemp -d "${TMPDIR:-.}/s3-selftest.XXXXXX") || exit 1
    trap 'rm -rf "$test_dir"' EXIT
    printf '0\n' > "$test_dir/page"
    mode=success
    aws() {
      local operation="$2" request count
      shift 2
      printf '%s\n' "$operation" >> "$test_dir/calls"
      [[ "$*" == *'--bucket eks-dual-36687d47d-7ce10-elastic-backup'* ]] || return 1
      case "$operation" in
        get-bucket-location) echo eu-west-2 ;;
        list-object-versions)
          [[ "$*" == *'--region eu-west-2 --max-keys 500 --no-paginate'* ]] || return 1
          [[ "$mode" != list_failure ]] || return 1
          count=$(< "$test_dir/page")
          printf '%s\n' "$((count + 1))" > "$test_dir/page"
          case "$count" in
            0) jq -nc '{IsTruncated:true, Versions:[range(0;499) | {Key:("snapshot/\"\\\n" + tostring), VersionId:"v1"}],
                 DeleteMarkers:[{Key:"snapshot/deleted", VersionId:"marker1"}]}' ;;
            1) echo '{"Versions":[{"Key":"snapshot/null","VersionId":"null"}]}' ;;
            *) echo '{"IsTruncated":false}' ;;
          esac ;;
        delete-objects)
          [[ "$*" == *'--region eu-west-2'* ]] || return 1
          while [[ $# -gt 0 ]]; do
            if [[ "$1" == --delete && "$2" == file:///dev/stdin ]]; then
              request=$(</dev/stdin)
              break
            fi
            shift
          done
          jq -e '.Quiet == true and (.Objects | length > 0 and length <= 500)
            and all(.Objects[]; (.Key | type == "string") and (.VersionId | type == "string"))' \
            <<< "$request" >/dev/null || return 1
          printf '%s\n' "$request" >> "$test_dir/deleted"
          if [[ "$mode" == delete_failure ]]; then
            echo '{"Errors":[{"Code":"AccessDenied"}]}'
          else
            : # Quiet:true success: the AWS CLI prints nothing.
          fi ;;
        *) return 1 ;;
      esac
    }
    remediate_s3_versions test clusters "$s3_scanner" || exit 1
    [[ "$(< "$test_dir/page")" == 3 ]] || exit 1
    jq -se 'map(.Objects) | add | length == 501 and
      any(.[]; .VersionId == "marker1") and any(.[]; .VersionId == "null")' \
      "$test_dir/deleted" >/dev/null || exit 1
    printf '0\n' > "$test_dir/page"
    mode=delete_failure
    if remediate_s3_versions test clusters "$s3_scanner"; then exit 1; fi
    mode=list_failure
    if remediate_s3_versions test clusters "$s3_scanner"; then exit 1; fi
    calls=$(wc -l < "$test_dir/calls")
    if remediate_s3_versions test clusters 'Error: emptying S3 Bucket (bad;command)'; then exit 1; fi
    [[ "$(wc -l < "$test_dir/calls")" == "$calls" ]] || exit 1
  ); then
    _expect "S3 handler drains bounded pages, versions and markers; rejects API failures" ok ok
  else
    _expect "S3 handler drains bounded pages, versions and markers; rejects API failures" failed ok
  fi

  _expect "DependencyViolation -> vpc dependencies" \
    "$(classify_destroy_error "$dep_violation" clusters)" "remediate_vpc_dependencies"
  _expect "OIDC config in use -> state removal" \
    "$(classify_destroy_error "$oidc_in_use" clusters)" "remediate_orphaned_oidc"
  _expect "broken trust policy -> account roles" \
    "$(classify_destroy_error "$trust_policy" clusters)" "remediate_broken_trust_policy"
  _expect "DeleteConflict -> detach IAM policies" \
    "$(classify_destroy_error "$delete_conflict" cluster)" "remediate_iam_attachments"
  _expect "CLUSTERS-MGMT-404 -> already gone" \
    "$(classify_destroy_error "$gone" cluster)" "already_gone"
  _expect "InvalidGlobalClusterStateFault -> detach Aurora members" \
    "$(classify_destroy_error "$global_state" infra/terraform)" "remediate_aurora_global"
  _expect "last master instance after failover -> detach Aurora members" \
    "$(classify_destroy_error "$last_master" infra/terraform)" "remediate_aurora_global"
  _expect "EIP left on a deleted interface -> release it" \
    "$(classify_destroy_error "$stale_eip" vpc/terraform)" "remediate_stale_eips"

  _expect "log tag keeps a module path with a slash" \
    "$(printf 'x\n' | tag_stream e2e-run1 app/terraform)" "[e2e-run1][app/terraform] | x"

  # A 404 only means "already gone" for a cluster module; anywhere else it is
  # an unclassified failure and must not be swallowed as success.
  _expect "404 on a non-cluster module is not success" \
    "$(classify_destroy_error "$gone" backup_bucket)" ""
  _expect "unrecognised error has no handler" \
    "$(classify_destroy_error "$unknown" clusters)" ""

  # Every handler the classifier can name has to be callable, or the loop would
  # dispatch into nothing and the error would look recovered.
  for got in remediate_vpc_dependencies remediate_orphaned_oidc \
             remediate_broken_trust_policy remediate_iam_attachments \
             remediate_aurora_global remediate_s3_versions remediate_stale_eips; do
    if declare -F "$got" >/dev/null; then
      echo "ok   handler $got is defined"
    else
      echo "FAIL handler $got is named by the classifier but not defined"
      failures=$((failures + 1))
    fi
  done

  # cloud-nuke deletes whatever its config matches. An EKS entry left unscoped
  # would take every cluster in the CI account, not just this group's, so the
  # scoping is asserted rather than assumed.
  if command -v yq >/dev/null 2>&1; then
    local scoped_config scoped_vpc scoped_eks
    scoped_config="$(mktemp)"
    cp "$SCRIPT_DIR/matching-vpc.yml" "$scoped_config"
    NAME_REGEX='^example-group(-|$)' yq eval \
      '.VPC.include.names_regex = [strenv(NAME_REGEX)] | .EKSCluster.include.names_regex = [strenv(NAME_REGEX)]' \
      -i "$scoped_config"
    scoped_vpc="$(yq eval '.VPC.include.names_regex[0]' "$scoped_config")"
    scoped_eks="$(yq eval '.EKSCluster.include.names_regex[0]' "$scoped_config")"
    rm -f "$scoped_config"

    _expect "cloud-nuke VPC target is scoped to the group" "$scoped_vpc" '^example-group(-|$)'
    _expect "cloud-nuke EKS target is scoped to the group" "$scoped_eks" '^example-group(-|$)'

    # The boundary is the point: a prefix-only pattern also matches every
    # longer id, which is how one group's nuke reaches another's VPCs.
    if printf 'example-group-1234-r0-vpc\n' | grep -Eq '^example-group(-|$)' &&
       ! printf 'example-group1234-r0-vpc\n' | grep -Eq '^example-group(-|$)'; then
      echo "ok   cloud-nuke pattern stops at the group boundary"
    else
      echo "FAIL cloud-nuke pattern leaks across ids sharing a prefix"
      failures=$((failures + 1))
    fi
  else
    echo "skip cloud-nuke scoping check: yq unavailable"
  fi

  # Both target forms callers pass, and the boundary between ids that share
  # a prefix. The run-suffix form matched nothing for a while, which made the
  # Terratest suites' per-run cleanup a silent no-op.
  keys='p/tfstate-ecsdr-123/app/terraform.tfstate
p/tfstate-ecsdr-1234/app/terraform.tfstate
p/main/tfstate-ecsdr-123/vpc/terraform.tfstate
p/tfstate-e2e-p-abc-run987/app/terraform.tfstate
p/tfstate-e2e-u-abc-run987/infra/terraform.tfstate
p/tfstate-e2e-p-abc-run9876/app/terraform.tfstate'
  _expect "target selects its own cluster, not one sharing its prefix" \
    "$(printf '%s\n' "$keys" | select_target_groups ecsdr-123 | paste -sd, -)" "ecsdr-123"
  # ECS Terratest groups are `<prefix>-run<id>`, their VPCs `<prefix>-r0-vpc`
  # and `<prefix>-byo-r0`. Matching on the group id found neither.
  _expect "run-suffixed group owns resources named after its prefix" \
    "$(resource_owner e2e-p-abc-run987)" "e2e-p-abc"
  _expect "a group without a run suffix owns its own name" \
    "$(resource_owner ecsdr-123)" "ecsdr-123"
  _expect "only a trailing run suffix is dropped" \
    "$(resource_owner e2e-run1-abc)" "e2e-run1-abc"
  _expect "run-suffix target selects every group of that run, and only it" \
    "$(printf '%s\n' "$keys" | select_target_groups run987/ | paste -sd, -)" "e2e-p-abc-run987,e2e-u-abc-run987"
  # ROSA dual-region passes the full pair of its two cluster names. Passing
  # only the base name once matched nothing, so its per-PR teardown reported
  # success with both clusters still running.
  pairs='p/main/tfstate-rosa-dr-abc-0-oOo-rosa-dr-abc-1/clusters.tfstate
p/main/tfstate-rosa-dr-abcd-0-oOo-rosa-dr-abcd-1/clusters.tfstate
p/main/tfstate-rosa-dr-abc-x-0-oOo-rosa-dr-abc-x-1/clusters.tfstate'
  _expect "ROSA pair target selects its own pair, not one sharing a prefix" \
    "$(printf '%s\n' "$pairs" | select_target_groups rosa-dr-abc-0-oOo-rosa-dr-abc-1 | paste -sd, -)" "rosa-dr-abc-0-oOo-rosa-dr-abc-1"

  # The last-module guard decides whether cloud-nuke may run at all. Nuking
  # before the VPC owner's turn deletes subnets and ENIs that the states still
  # queued behind it have in their own plans, so the guard is asserted against
  # a realistic ORDERED_MODULES rather than trusted.
  (
    RETRY_DESTROY=true
    CLEANUP_REGIONS="eu-west-2"
    # The permitted path goes on to `aws ec2 describe-vpcs` and `cloud-nuke`.
    # This runs as a pre-commit hook on machines that hold AWS credentials, so
    # both are replaced by fakes that only record the call: a selftest must
    # never be able to delete infrastructure.
    nuke_bin=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho vpc-0selftest\n' >"$nuke_bin/aws"
    printf '#!/usr/bin/env bash\necho "NUKE $*" >>"%s/calls"\n' "$nuke_bin" >"$nuke_bin/cloud-nuke"
    chmod +x "$nuke_bin/aws" "$nuke_bin/cloud-nuke"
    # Subshell-local on purpose, like ORDERED_MODULES below: the fakes must
    # not shadow the real tools for the rest of the script.
    # shellcheck disable=SC2030
    PATH="$nuke_bin:$PATH"
    # Subshell-local on purpose: the selftest must not leak its ORDERED_MODULES
    # into the real destruction order below.
    # shellcheck disable=SC2030
    ORDERED_MODULES=(app/terraform infra/terraform vpc/terraform fixture/terraform)
    # A greenfield group: every declared module but the BYO-VPC fixture.
    module_state_exists() { [[ "$2" != fixture/terraform ]]; }

    early=$(nuke_vpcs_in_cleanup_regions g infra/terraform "$(mktemp -d)" 2>&1)
    if [[ "$early" == *"Skipping the cloud-nuke fallback"* && ! -s "$nuke_bin/calls" ]]; then
      echo "ok   cloud-nuke skipped while a later module still owns the VPC"
    else
      echo "FAIL cloud-nuke ran for infra/terraform, before vpc/terraform was destroyed"; exit 1
    fi

    # vpc/terraform is the owner here even though fixture/terraform is declared
    # after it: the group has no fixture state. Gating on the declared order
    # skipped it, so greenfield groups never reached the fallback. Asserted on
    # the fake's record, so "ran" means cloud-nuke was really invoked.
    last=$(nuke_vpcs_in_cleanup_regions g vpc/terraform "$(mktemp -d)" 2>&1)
    if grep -q -- "--region eu-west-2" "$nuke_bin/calls" 2>/dev/null; then
      echo "ok   cloud-nuke runs for the module that owns the VPC"
    else
      echo "FAIL cloud-nuke never ran for the VPC owner: $last"; exit 1
    fi
  ) || failures=$((failures + 1))

  # The EIP lives in one of the declared regions, which the error does not
  # name. The handler has to find it there, drop the stale association and
  # release it, in that region — a release sent to the wrong region is a no-op
  # and the VPC still leaks.
  (
    eip_bin=$(mktemp -d)
    cat >"$eip_bin/aws" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_CALLS"
case "$*" in
  *"describe-addresses --region eu-west-3"*) echo "eipassoc-08223567b1693755f" ;;
  *describe-addresses*) exit 254 ;;
esac
FAKE
    chmod +x "$eip_bin/aws"
    # Each case owns its subshell and its own call log, like PATH above.
    # shellcheck disable=SC2030
    export FAKE_CALLS="$eip_bin/calls"
    : >"$FAKE_CALLS"
    # shellcheck disable=SC2030,SC2031
    PATH="$eip_bin:$PATH"
    CLEANUP_REGIONS="eu-west-2 eu-west-3"

    remediate_stale_eips g vpc/terraform "$stale_eip" >/dev/null 2>&1
    if grep -q "disassociate-address --region eu-west-3 --association-id eipassoc-08223567b1693755f" "$FAKE_CALLS" &&
       grep -q "release-address --region eu-west-3 --allocation-id eipalloc-05ae99ac0dafa1cf0" "$FAKE_CALLS" &&
       ! grep -q "release-address --region eu-west-2" "$FAKE_CALLS"; then
      echo "ok   stale EIP is disassociated and released in its own region"
    else
      echo "FAIL stale EIP handler did not release it in eu-west-3:"; cat "$FAKE_CALLS"
      exit 1
    fi
  ) || failures=$((failures + 1))

  # The instance-lookup branch resolves an instance name to a global cluster
  # through three chained describe calls. A wrong ARN field index or regex
  # yields an empty result, the handler reports "nothing to detach" and
  # returns 0, and the retry loop then exhausts itself with the global cluster
  # still blocking the destroy — silently, and billing throughout.
  (
    fake_bin=$(mktemp -d)
    cat >"$fake_bin/aws" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"describe-global-clusters --query"*) echo "my-global-db" ;;
  *"--global-cluster-identifier my-global-db --query"*)
    echo "arn:aws:rds:eu-west-3:1:cluster:member-r1" ;;
  # Region-sensitive on purpose: the member lives in eu-west-3, so a lookup
  # that reads the wrong ARN field queries the wrong region and finds nothing.
  *"describe-db-clusters --region eu-west-3 --db-cluster-identifier member-r1"*) echo "the-instance" ;;
  *describe-db-clusters*) ;;
  *remove-from-global-cluster*) echo "REMOVE $*" >>"$FAKE_CALLS" ;;
esac
FAKE
    chmod +x "$fake_bin/aws"
    # shellcheck disable=SC2031  # this case's own call log, see the EIP case
    export FAKE_CALLS="$fake_bin/calls"
    : >"$FAKE_CALLS"
    # SC2031: each case gets its own subshell and its own fakes; the PATH set
    # in the cloud-nuke case above never reaches this one, by design.
    # shellcheck disable=SC2031
    PATH="$fake_bin:$PATH"

    # No "RDS Global Cluster (...)" in the text, so only the instance-lookup
    # branch can find the owner.
    err_text="Error: deleting RDS Cluster Instance (the-instance): Cannot delete the last instance of the master cluster"
    out=$(remediate_aurora_global g infra/terraform "$err_text" 2>&1)

    # The region matters as much as the ARN: remove-from-global-cluster has to
    # go to the member's own region, which after a failover is not AWS_REGION.
    if grep -q "remove-from-global-cluster" "$FAKE_CALLS" &&
       grep -q -- "--region eu-west-3" "$FAKE_CALLS" &&
       grep -q "arn:aws:rds:eu-west-3:1:cluster:member-r1" "$FAKE_CALLS"; then
      echo "ok   Aurora handler resolves a global cluster from the instance name"
    else
      echo "FAIL Aurora handler detached nothing from an instance-only error: $out"
      exit 1
    fi
  ) || failures=$((failures + 1))

  [[ "$failures" -eq 0 ]] || return 1
}
