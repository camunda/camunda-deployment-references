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
		wantError, wipe  bool
	}{
		{"writer switch", "healthy", "Failback complete", []string{"--switch-writer"}, false, true},
		{"no writer switch", "healthy", "Failback complete", nil, false, true},
		// The gateway going away after the zone is re-added must be reported as
		// such, not as a count of zero brokers.
		{"gateway lost after re-add", "alb-down", "stopped answering", nil, true, true},
		// Pending brokers would start against EFS while the wipe deletes it.
		{"service not scaled down", "pending", "not scaled to 0", nil, true, false},
		// An interrupted run can leave a wipe that would delete data after this one.
		{"leftover wipe task", "leftover", "left by an earlier run", nil, false, true},
		{"wipe still stopping", "stopping", "Waiting for earlier tasks", nil, false, true},
		// A zone still in the partition distribution hosts live replicas.
		{"zone still present", "zone-present", "keeping its data", nil, false, false},
		{"keep data", "healthy", "--keep-data given", []string{"--keep-data"}, false, false},
		{"wipe fails", "wipe-fails", "exit code 1", nil, true, true},
		{"wipe not placed", "not-placed", "could not start the wipe task", nil, true, false},
		// A wipe left by a timed-out run must stop before brokers start, even
		// when this run keeps the data.
		{"keep data with leftover wipe", "leftover", "left by an earlier run", []string{"--keep-data"}, false, false},
		// Just after run-task, DescribeTasks can report the task as MISSING.
		{"wipe briefly missing", "missing", "Failback complete", nil, false, true},
		{"task state unreadable", "describe-fails", "could not be read", nil, true, true},
		// The script dies before it saves the task ARN, as on an interruption.
		{"run-task output lost", "run-task-dies", "", nil, true, true},
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
mgmt_zone_present() { [ -f "$FAKE_DIR/added" ] || [ "$MODE" = zone-present ]; }
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
  *describe-services*)
    if [ "$MODE" = pending ]; then echo '{"taskDefinition":"td","networkConfiguration":{},"desiredCount":2,"pendingCount":2,"runningCount":0}'
    else echo '{"taskDefinition":"td","networkConfiguration":{},"desiredCount":0,"pendingCount":0,"runningCount":0}'; fi ;;
  # ECS rejects startedBy combined with any other filter.
  *list-tasks*--started-by*--desired-status*|*list-tasks*--desired-status*--started-by*) echo "startedBy must be the only filter" >&2; exit 254 ;;
  *list-tasks*--started-by*)
    if [ "$MODE" = leftover ]; then echo '["old-wipe"]'
    elif [ "$MODE" = run-task-dies ] && [ -f "$FAKE_DIR/wiped" ]; then echo '["task"]'
    else echo '[]'; fi ;;
  *list-tasks*--desired-status\ STOPPED*) if [ "$MODE" = stopping ]; then echo '["old-wipe"]'; else echo '[]'; fi ;;
  *list-tasks*) echo '[]' ;;
  *stop-task*) echo "$*" >> "$FAKE_DIR/stopped" ;;
  *describe-task-definition*)
    echo '{"family":"f","volumes":[{"name":"camunda-volume"}],"containerDefinitions":[{"name":"orchestration-cluster","image":"i","mountPoints":[{"sourceVolume":"camunda-volume"}]}]}' ;;
  *deregister-task-definition*) touch "$FAKE_DIR/deregistered" ;;
  *register-task-definition*) touch "$FAKE_DIR/registered"; echo wipe-td ;;
  *run-task*)
    if [ "$MODE" = not-placed ]; then echo '{"tasks":[],"failures":[{"reason":"RESOURCE:ENI"}]}'; exit 0; fi
    # The data must be gone before any broker of the zone starts again.
    [ ! -f "$FAKE_DIR/scaledup" ] && touch "$FAKE_DIR/wiped"
    if [ "$MODE" = run-task-dies ]; then exit 255; fi
    echo '{"tasks":[{"taskArn":"task"}],"failures":[]}' ;;
  *describe-tasks*--query*)
    # No exit code exists before the task was seen STOPPED.
    if [ "$MODE" = missing ] && [ ! -f "$FAKE_DIR/stopped-seen" ]; then echo None
    elif [ "$MODE" = wipe-fails ]; then echo 1; else echo 0; fi ;;
  *describe-tasks*)
    if [ "$MODE" = describe-fails ]; then exit 254; fi
    if [ "$MODE" = missing ] && [ ! -f "$FAKE_DIR/seen" ]; then
      touch "$FAKE_DIR/seen"; echo '{"tasks":[],"failures":[{"arn":"task","reason":"MISSING"}]}'; exit 0
    fi
    touch "$FAKE_DIR/stopped-seen"
    echo '{"tasks":[{"lastStatus":"STOPPED"}],"failures":[]}' ;;
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
				"LEADER_SETTLE_TIMEOUT=2", "MGMT_TOPOLOGY_POLL_INTERVAL=0", "WIPE_POLL_INTERVAL=0")

			// When
			out, err := cmd.CombinedOutput()

			// Then
			if (err != nil) != tc.wantError || !strings.Contains(string(out), tc.want) {
				t.Fatalf("got %v, wantError=%t, missing %q\n%s", err, tc.wantError, tc.want, out)
			}
			if _, err := os.Stat(filepath.Join(fake, "wiped")); (err == nil) != tc.wipe {
				t.Fatalf("wipe ran=%t, want %t (#3766)\n%s", err == nil, tc.wipe, out)
			}
			// A wipe that may still run when the script fails must be asked to stop.
			stopped, _ := os.ReadFile(filepath.Join(fake, "stopped"))
			if strings.Contains(" wipe-fails describe-fails run-task-dies ", " "+tc.mode+" ") && !strings.Contains(string(stopped), "--task task") {
				t.Fatalf("wipe task was not stopped on failure\n%s", out)
			}
			if tc.mode == "leftover" && !strings.Contains(string(stopped), "--task old-wipe") {
				t.Fatalf("leftover wipe task was not stopped\n%s", out)
			}
			_, registered := os.Stat(filepath.Join(fake, "registered"))
			_, deregistered := os.Stat(filepath.Join(fake, "deregistered"))
			if (registered == nil) != (deregistered == nil) {
				t.Fatalf("wipe task definition registered=%t, deregistered=%t\n%s", registered == nil, deregistered == nil, out)
			}
		})
	}
}
