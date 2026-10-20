package helpers

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// topology renders a /v2/topology body. Each zone contributes `brokers`
// brokers; the leading zone owns one leader per partition and the other zone
// holds the same partitions as follower replicas, which is the shape a healthy
// dual-region cluster reports.
func topology(partitions int, leaderZone string, zones ...string) string {
	var bs []string
	for _, zone := range zones {
		for b := 0; b < 4; b++ {
			var ps []string
			for p := b*partitions/4 + 1; p <= (b+1)*partitions/4; p++ {
				role := "follower"
				if zone == leaderZone {
					role = "leader"
				}
				ps = append(ps, fmt.Sprintf(`{"partitionId":%d,"role":%q}`, p, role))
			}
			bs = append(bs, fmt.Sprintf(`{"brokerId":"%s_%d","partitions":[%s]}`,
				zone, b, strings.Join(ps, ",")))
		}
	}
	return fmt.Sprintf(`{"brokers":[%s],"clusterSize":%d,"replicationFactor":2}`,
		strings.Join(bs, ","), len(zones)*4)
}

// failback.sh runs end to end against fakes. It had no offline coverage, and a
// name set only on the failure path of the Step 6 assertion got past review and
// every local hook: the script reached its closing summary, read $BROKERS under
// `set -u`, and aborted after a failback that had already succeeded.
func TestFailbackCompletes(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name, mode, want string
		args             []string
		wantError        bool
	}{
		{"writer switch", "healthy", "Failback complete", []string{"--switch-writer"}, false},
		{"no writer switch", "healthy", "Failback complete", nil, false},
		// The gateway going away after the zone is re-added must be reported as
		// such, not as a count of zero brokers.
		{"gateway lost after re-add", "alb-down", "stopped answering", nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// Given: offline CLI and management API responses for one failback.
			fake := t.TempDir()
			body, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", "failback.sh"))
			if err != nil {
				t.Fatal(err)
			}

			surviving := topology(8, "eu-west-3", "eu-west-3")
			restored := topology(8, "eu-west-3", "eu-west-3", "eu-west-2")

			files := map[string]string{
				"failback.sh": string(body),
				// Sources the real helper, so the polling and counting code the
				// assertions depend on is the shipped implementation.
				"zeebe_management_api.sh": `. "` + realMgmtHelper(t) + `"
mgmt_log() { echo "$*"; }
mgmt_err() { echo "$*" >&2; }
mgmt_tunnel_open() { return 0; }
mgmt_tunnel_close() { :; }
mgmt_topology_summary() { :; }
mgmt_zone_present() { [ -f "$FAKE_DIR/added" ]; }
mgmt_request() { touch "$FAKE_DIR/added"; echo '{"changeId":"2","plannedChanges":[]}'; }
mgmt_wait_change() { return 0; }
`,
				"aurora.sh": `aurora_switch_to() { aws rds failover-global-cluster; }
`,
				"aws": `#!/usr/bin/env bash
case "$*" in
  # Two members, so Step 1 has nothing to re-attach.
  *describe-global-clusters*)
    echo '[{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false}]' ;;
  *list-services*) echo "svc-oc" ;;
  *describe-services*) echo '{"taskDefinition":"td","networkConfiguration":{},"runningCount":0}' ;;
  *describe-task-definition*)
    echo '{"family":"f","volumes":[{"name":"camunda-volume"}],"containerDefinitions":[{"name":"orchestration-cluster","image":"i","mountPoints":[{"sourceVolume":"camunda-volume"}]}]}' ;;
  *register-task-definition*) echo wipe-td ;;
  # The data must be gone before any broker of the zone starts again.
  *run-task*) [ ! -f "$FAKE_DIR/scaledup" ] && touch "$FAKE_DIR/wiped"; echo task ;;
  *describe-tasks*) echo 0 ;;
  *update-service*) touch "$FAKE_DIR/scaledup" ;;
  *failover-global-cluster*) echo PROMOTED >&2 ;;
  *describe-db-clusters*) echo available ;;
esac
`,
				"curl": `#!/usr/bin/env bash
# Only the recovered zone's brokers appear once ECS has been scaled back up,
# so Step 2 reads the surviving count before they join.
if [ "$MODE" = alb-down ] && [ -f "$FAKE_DIR/added" ]; then exit 7; fi
if [ -f "$FAKE_DIR/scaledup" ]; then cat "$FAKE_DIR/restored.json"; else cat "$FAKE_DIR/surviving.json"; fi
`,
				"surviving.json": surviving,
				"restored.json":  restored,
			}
			for name, content := range files {
				if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
					t.Fatal(err)
				}
			}

			cmd := exec.Command("bash", append([]string{filepath.Join(fake, "failback.sh")}, tc.args...)...)
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake, "MODE="+tc.mode,
				"REGION_0=eu-west-2", "REGION_1=eu-west-3", "CLUSTER_0=a", "CLUSTER_1=b",
				"ALB_ENDPOINT_0=a", "ALB_ENDPOINT_1=b", "ADMIN_USER=admin", "ADMIN_PASS=test",
				"AURORA_GLOBAL_CLUSTER_ID=g", "AURORA_ENGINE=aurora-postgresql",
				"LEADER_SETTLE_TIMEOUT=2", "MGMT_TOPOLOGY_POLL_INTERVAL=0")

			// When
			out, err := cmd.CombinedOutput()

			// Then
			if (err != nil) != tc.wantError || !strings.Contains(string(out), tc.want) {
				t.Fatalf("got %v, wantError=%t, missing %q\n%s", err, tc.wantError, tc.want, out)
			}
			if _, err := os.Stat(filepath.Join(fake, "wiped")); err != nil {
				t.Fatalf("primary storage was not wiped before the scale-up (#3766)\n%s", out)
			}
		})
	}
}
