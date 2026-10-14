package helpers

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMgmtWaitChangeTimeoutDumpsLastResponse(t *testing.T) {
	t.Parallel()
	for _, format := range []string{"pretty", "raw"} {
		t.Run(format, func(t *testing.T) {
			// Given: one stalled response and a clock advanced without sleeping.
			cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./zeebe_management_api.sh
mgmt_get() {
    [ "$1" = /actuator/cluster/changes/7 ] || return 1
    echo '{"status":"IN_PROGRESS","pending":[{"operation":"REMOVE","brokerId":"survivor_2"}]}'
}
sleep() { :; }
if [ "$1" = raw ]; then
    jq() { [ "$1" != . ] && command jq "$@"; }
fi
mgmt_wait_change 7 5`, "test", format)
			cmd.Dir = filepath.Join("..", "..", "..", "procedure")
			var stderr bytes.Buffer
			cmd.Stderr = &stderr
			// When
			stdout, err := cmd.Output()
			// Then: timeout remains exit 1, with the full payload only on stderr.
			var exit *exec.ExitError
			require.ErrorAs(t, err, &exit)
			require.Equal(t, 1, exit.ExitCode())
			require.Contains(t, stderr.String(), "survivor_2")
			require.NotContains(t, string(stdout), "survivor_2")
			if format == "pretty" {
				require.Contains(t, stderr.String(), "\n  \"status\": \"IN_PROGRESS\"")
			} else {
				require.Contains(t, stderr.String(), `{"status":"IN_PROGRESS","pending":[{"operation":"REMOVE","brokerId":"survivor_2"}]}`)
			}
		})
	}
}

func TestMgmtWaitChangeZeroTimeout(t *testing.T) {
	t.Parallel()
	cmd := exec.Command("bash", "-c", `set -euo pipefail
. ./zeebe_management_api.sh
mgmt_wait_change 7 0`)
	cmd.Dir = filepath.Join("..", "..", "..", "procedure")
	out, err := cmd.CombinedOutput()
	var exit *exec.ExitError
	require.ErrorAs(t, err, &exit)
	require.Equal(t, 1, exit.ExitCode())
	require.NotContains(t, string(out), "unbound variable")
}
