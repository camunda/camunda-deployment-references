package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// runRequest calls camunda::management with kubectl and curl replaced by stubs.
// The curl stub fails with exit 7 ("could not connect") on its first
// failConnects calls, then exits with finalExit and answers HTTP finalStatus.
func runRequest(t *testing.T, method string, failConnects, finalExit int, finalStatus string) (calls int, out string, err error) {
	t.Helper()
	bin := t.TempDir()
	count := filepath.Join(bin, "count")

	stubs := map[string]string{
		"kubectl": "#!/bin/bash\nexec sleep 30\n",
		"curl": `#!/bin/bash
n=$(cat "` + count + `" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"` + count + `"
if [ "$n" -le "$FAIL_CONNECTS" ]; then printf '\n000'; exit 7; fi
printf '{}\n%s' "$FINAL_STATUS"; exit "$FINAL_EXIT"
`,
	}
	for name, body := range stubs {
		if werr := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); werr != nil {
			t.Fatal(werr)
		}
	}

	cmd := exec.Command("bash", "-c", `
. ./lib-management-api.sh
sleep() { :; }
camunda::management cluster-london "$METHOD" /actuator/cluster
`)
	cmd.Dir = ProcedureDir(t)
	cmd.Env = append(os.Environ(),
		"PATH="+bin+":"+os.Getenv("PATH"),
		"CAMUNDA_NAMESPACE=camunda", "CAMUNDA_RELEASE_NAME=camunda", "MANAGEMENT_LOCAL_PORT=9600",
		"METHOD="+method,
		"FAIL_CONNECTS="+strconv.Itoa(failConnects), "FINAL_EXIT="+strconv.Itoa(finalExit), "FINAL_STATUS="+finalStatus,
	)
	o, err := cmd.CombinedOutput()
	raw, _ := os.ReadFile(count)
	n, _ := strconv.Atoi(strings.TrimSpace(string(raw)))
	return n, string(o), err
}

func TestRequestRetriesWhenNothingListens(t *testing.T) {
	t.Parallel()

	// Given: the tunnel refuses twice, then the gateway answers.
	// When: a POST goes through the management helper.
	calls, out, err := runRequest(t, "POST", 2, 0, "200")

	// Then: the request succeeds on the third attempt.
	if err != nil || calls != 3 {
		t.Fatalf("expected success after 3 attempts, got %d attempts, err %v:\n%s", calls, err, out)
	}
}

func TestRequestDoesNotRetryOtherCurlFailures(t *testing.T) {
	t.Parallel()

	// Given: curl reached the server and timed out (exit 28), so the request may have been applied.
	// When: a DELETE goes through the management helper.
	calls, out, err := runRequest(t, "DELETE", 0, 28, "000")

	// Then: it fails after one attempt instead of sending the DELETE again.
	if err == nil || calls != 1 {
		t.Fatalf("expected one attempt and a failure, got %d attempts, err %v:\n%s", calls, err, out)
	}
}

func TestRequestReportsTerminalConnectFailureWithoutRetryMessage(t *testing.T) {
	t.Parallel()

	// Given: the tunnel never comes up.
	// When: a GET goes through the management helper.
	calls, out, err := runRequest(t, "GET", 9, 0, "200")

	// Then: it stops after 5 attempts and announces only the 4 retries that happen.
	if err == nil || calls != 5 || strings.Count(out, "retrying") != 4 {
		t.Fatalf("expected 5 attempts and 4 retry notices, got %d attempts, err %v:\n%s", calls, err, out)
	}
}
