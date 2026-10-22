package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestFailoverRecoveryOrdering(t *testing.T) {
	for _, tc := range []struct {
		name, mode, want string
		args             []string
		wantError        bool
	}{
		{"missing writer", "empty", "No Aurora writer ARN", nil, true},
		{"leader failure", "leader-failure", "PROMOTED", nil, true},
		{"removed zone", "absent", "PROMOTED", nil, false},
		{"dry run", "dry-run", "would promote arn:aws:rds:eu-west-3:1:cluster:b", []string{"--dry-run"}, false},
		{"dry run, missing writer", "nowriter", "No Aurora writer ARN", []string{"--dry-run"}, true},
		{"dry run, no surviving member", "nosurvivor", "No Aurora member in", []string{"--dry-run"}, true},
		// The leader check polls, so an ALB that refuses a couple of reads
		// while the brokers follow the new writer is not a failover failure.
		{"surviving ALB flaps", "alb-flaps", "Every partition has a leader", nil, false},
		// And one that never answers reports that, rather than the empty
		// counts of "Only  of  partitions have a leader".
		{"surviving ALB never answers", "alb-down", "stopped answering", nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// Given: offline CLI and management API responses for one recovery path.
			fake := t.TempDir()
			body, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", "failover.sh"))
			if err != nil {
				t.Fatal(err)
			}
			helpers, err := os.ReadFile(filepath.Join("..", "..", "..", "procedure", "aurora.sh"))
			if err != nil {
				t.Fatal(err)
			}
			files := map[string]string{
				"failover.sh": string(body),
				// Sources the real helper first, so mgmt_topology_settled and
				// mgmt_topology_count are the shipped implementations rather than
				// stubs; only the functions that need AWS are overridden below.
				"zeebe_management_api.sh": `. "` + realMgmtHelper(t) + `"
mgmt_log() { echo "$*"; }
mgmt_err() { echo "$*" >&2; }
mgmt_tunnel_open() { return 0; }
mgmt_tunnel_close() { :; }
mgmt_topology_summary() { :; }
mgmt_zone_present() {
  [ "$MODE" = absent ] && return 1
  [ -f "$FAKE_DIR/deleted" ] && return 1
  return 0
}
mgmt_request() {
  [ "$MODE" = absent ] && { echo duplicate-delete >&2; return 1; }
  touch "$FAKE_DIR/deleted"
  echo '{"changeId":"1","plannedChanges":[]}'
}
mgmt_wait_change() { return 0; }
`,
				"aurora.sh": string(helpers) + `
aurora_settled_global() { aws rds describe-global-clusters | jq '{GlobalClusterMembers: .}'; }
aurora_switch_to() { aws rds failover-global-cluster; }
`,
				"aws": `#!/usr/bin/env bash
case "$*" in
  *describe-global-clusters*)
    [ "$MODE" = empty ] && { echo '[]'; exit 0; }
    [ "$MODE" = nosurvivor ] && { echo '[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true}]'; exit 0; }
    [ "$MODE" = nowriter ] && { echo '[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]'; exit 0; }
    echo '[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]' ;;
  *describe-db-clusters*) echo available ;;
  *failover-global-cluster*) echo PROMOTED >&2 ;;
esac
`,
				"curl": `#!/usr/bin/env bash
healthy='{"brokers":[{"partitions":[{"partitionId":1,"role":"leader"}]}]}'
case "$MODE" in
  leader-failure) echo '{"brokers":[]}' ;;
  # Both degrade only once the zone is gone, so Step 0's reachability check
  # still passes and the failure lands on Step 6 the way it did in CI.
  # alb-flaps refuses two reads the way the ALB does while the surviving
  # region reconnects to the promoted Aurora writer, then answers.
  alb-flaps)
    [ -f "$FAKE_DIR/deleted" ] || { echo "$healthy"; exit 0; }
    n=$(cat "$FAKE_DIR/curls" 2>/dev/null || echo 0); echo $((n + 1)) >"$FAKE_DIR/curls"
    [ "$n" -lt 2 ] && exit 7
    echo "$healthy" ;;
  alb-down)
    [ -f "$FAKE_DIR/deleted" ] || { echo "$healthy"; exit 0; }
    exit 7 ;;
  *) echo "$healthy" ;;
esac
`,
			}
			for name, content := range files {
				if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			cmd := exec.Command("bash", append([]string{filepath.Join(fake, "failover.sh"), "--keep-tasks"}, tc.args...)...)
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake, "MODE="+tc.mode,
				"REGION_0=eu-west-2", "REGION_1=eu-west-3", "CLUSTER_0=a", "CLUSTER_1=b",
				"ALB_ENDPOINT_0=a", "ALB_ENDPOINT_1=b", "ADMIN_USER=admin", "ADMIN_PASS=test", "AURORA_GLOBAL_CLUSTER_ID=g",
				"LEADER_SETTLE_TIMEOUT=2", "MGMT_TOPOLOGY_POLL_INTERVAL=0")
			// When
			out, err := cmd.CombinedOutput()
			// Then
			if (err != nil) != tc.wantError || !strings.Contains(string(out), tc.want) {
				t.Fatalf("got %v, wantError=%t, missing %q\n%s", err, tc.wantError, tc.want, out)
			}
		})
	}
}

// Right after a region loss the first tunnel can fail while the surviving
// brokers restart. mgmt_tunnel_open retries, and gives up after the last try.
func TestMgmtTunnelOpenRetries(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		attempts string
		wantErr  bool
	}{{"3", false}, {"2", true}} {
		cmd := exec.Command("bash", "-c", `set -uo pipefail
. ./zeebe_management_api.sh
calls=0
_mgmt_tunnel_open_once() { calls=$((calls + 1)); [ "$calls" -ge 3 ]; }
mgmt_tunnel_open eu-west-3 c p`)
		cmd.Dir = filepath.Join("..", "..", "..", "procedure")
		cmd.Env = append(os.Environ(), "MGMT_TUNNEL_ATTEMPTS="+tc.attempts, "MGMT_TUNNEL_RETRY_SECONDS=0")
		out, err := cmd.CombinedOutput()
		if (err != nil) != tc.wantErr {
			t.Errorf("%s attempts: err=%v\n%s", tc.attempts, err, out)
		}
	}
}

// realMgmtHelper is the shipped zeebe_management_api.sh. The fake sources it so
// the pure-shell helpers are exercised rather than stubbed; the AWS-dependent
// functions are redefined after the source.
func realMgmtHelper(t *testing.T) string {
	t.Helper()
	path, err := filepath.Abs(filepath.Join("..", "..", "..", "procedure", "zeebe_management_api.sh"))
	if err != nil {
		t.Fatal(err)
	}
	return path
}
