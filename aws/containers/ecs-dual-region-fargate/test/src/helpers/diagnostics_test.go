package helpers

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestBrokerLogsFailureLifecycle(t *testing.T) {
	for _, mode := range []string{"success", "failure", "capture-failure"} {
		t.Run(mode, func(t *testing.T) {
			// Given: a child test can intentionally fail without failing this test.
			dir := t.TempDir()
			fake := `#!/usr/bin/env bash
echo capture >> "$TRACE"
echo 'broker evidence'
[ "$PROBE" != capture-failure ]
`
			require.NoError(t, os.WriteFile(filepath.Join(dir, "aws"), []byte(fake), 0o755))
			binary, err := os.Executable()
			require.NoError(t, err)
			cmd := exec.Command(binary, "-test.run=^TestBrokerLogsLifecycleProbe$")
			cmd.Env = append(os.Environ(), "PROBE="+mode, "TRACE="+filepath.Join(dir, "trace"),
				"TEST_DIAGNOSTICS_DIR="+dir, "PATH="+dir+":"+os.Getenv("PATH"))
			// When
			out, err := cmd.CombinedOutput()
			// Then: even a failed capture precedes cleanup; success makes no AWS call.
			trace, readErr := os.ReadFile(filepath.Join(dir, "trace"))
			require.NoError(t, readErr, string(out))
			if mode == "success" {
				require.NoError(t, err, string(out))
				require.Equal(t, "cleanup\n", string(trace))
			} else {
				require.Error(t, err)
				require.Equal(t, "capture\ncleanup\n", string(trace))
				body, readErr := os.ReadFile(filepath.Join(dir, "TestBrokerLogsLifecycleProbe", "surviving-brokers.log"))
				require.NoError(t, readErr)
				require.Contains(t, string(body), "broker evidence")
			}
		})
	}
}

func TestBrokerLogsLifecycleProbe(t *testing.T) {
	mode := os.Getenv("PROBE")
	if mode == "" {
		t.Skip("subprocess probe")
	}
	t.Cleanup(func() {
		file, err := os.OpenFile(os.Getenv("TRACE"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
		require.NoError(t, err)
		_, err = file.WriteString("cleanup\n")
		require.NoError(t, err)
		require.NoError(t, file.Close())
	})
	defer CaptureBrokerLogsOnFailure(t, BrokerLogs{Region: "eu-west-3", LogGroup: "/ecs/test", Start: time.UnixMilli(1234)})
	if mode != "success" {
		t.Fatal("simulated deployment or procedure failure")
	}
}

func TestBrokerLogsCapture(t *testing.T) {
	for _, result := range []string{"success", "failure"} {
		t.Run(result, func(t *testing.T) {
			// Given
			dir := t.TempDir()
			fake := `#!/usr/bin/env bash
printf '%s\n' "$@"
echo 'broker log event'
if [ "$RESULT" = failure ]; then echo 'AccessDeniedException' >&2; exit 1; fi
`
			require.NoError(t, os.WriteFile(filepath.Join(dir, "aws"), []byte(fake), 0o755))
			t.Setenv("PATH", dir+":"+os.Getenv("PATH"))
			t.Setenv("RESULT", result)
			logs := BrokerLogs{Profile: "test-profile", Region: "eu-west-3", LogGroup: "/ecs/test-r1-oc-camunda", Start: time.UnixMilli(1234)}
			path := filepath.Join(dir, "brokers.log")
			// When
			err := logs.capture(context.Background(), path, time.UnixMilli(5678))
			// Then: CLI pagination stays enabled and failures retain their output.
			if result == "success" {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
			out, readErr := os.ReadFile(path)
			require.NoError(t, readErr)
			require.Contains(t, string(out), "logs\nfilter-log-events\n")
			require.Contains(t, string(out), "--log-group-name\n/ecs/test-r1-oc-camunda\n")
			require.Contains(t, string(out), "--start-time\n1234\n--end-time\n5678\n")
			require.Contains(t, string(out), "--region\neu-west-3\n")
			require.Contains(t, string(out), "--profile\ntest-profile\n")
			require.NotContains(t, string(out), "--no-paginate")
			require.Contains(t, string(out), "broker log event")
			if result == "failure" {
				require.Contains(t, string(out), "AccessDeniedException")
			}
		})
	}
}
