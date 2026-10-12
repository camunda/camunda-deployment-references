package helpers

import (
	"os/exec"
	"strings"
	"testing"
)

// The management API still reports the previous change as COMPLETED for a
// moment after a new one is requested. The wait must hold out for the change
// it was given, the same bug class as the Aurora switchover in #3572.
const fakeClusterAPI = `set -euo pipefail
source ./lib-management-api.sh
# Runs in a command substitution, so the count lives in a file.
counter="$(mktemp)"
camunda::management() {
    local calls=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
    echo "$calls" > "$counter"
    case "$calls" in
        1) echo '{"lastChange":{"id":6,"status":"COMPLETED"}}' ;;
        2) echo '{"pendingChange":{"id":7},"lastChange":{"id":6,"status":"COMPLETED"}}' ;;
        *) echo "{\"lastChange\":{\"id\":7,\"status\":\"$FINAL\"}}" ;;
    esac
}
CLUSTER_CHANGE_POLL_SECONDS=0 camunda::wait_for_cluster_change ctx 7 60
echo "polls=$(cat "$counter")"; rm -f "$counter"`

func runWaitForClusterChange(t *testing.T, final string) (string, error) {
	t.Helper()
	cmd := exec.Command("bash", "-c", fakeClusterAPI)
	cmd.Dir = ProcedureDir(t)
	cmd.Env = append(cmd.Environ(), "FINAL="+final, "TMPDIR="+t.TempDir())
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func TestWaitForClusterChangeIgnoresThePreviousChange(t *testing.T) {
	t.Parallel()

	out, err := runWaitForClusterChange(t, "COMPLETED")
	if err != nil || !strings.Contains(out, "polls=3") {
		t.Fatalf("returned before change 7 completed: %v\n%s", err, out)
	}
}

func TestWaitForClusterChangeFailsOnAFailedChange(t *testing.T) {
	t.Parallel()

	out, err := runWaitForClusterChange(t, "FAILED")
	if err == nil || !strings.Contains(out, "ended as FAILED") {
		t.Fatalf("expected a failure, got %v\n%s", err, out)
	}
}
