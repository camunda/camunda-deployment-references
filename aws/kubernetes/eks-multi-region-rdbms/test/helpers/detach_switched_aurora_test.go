package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// runDetach runs test/detach-switched-aurora-members.sh against a stubbed AWS
// CLI holding one global cluster whose writer lives in writerRegion and whose
// Terraform state was last written ageHours ago. It returns every AWS call.
func runDetach(t *testing.T, match, minAge, writerRegion string, ageHours int) (calls []string, out string) {
	t.Helper()
	return runDetachSettling(t, match, minAge, "", writerRegion, ageHours)
}

// runDetachSettling is runDetach with a switchover in progress on the first
// listing: the global cluster then reports pendingWriterRegion as writer and a
// FailoverState, and every later read reports the settled writerRegion.
func runDetachSettling(t *testing.T, match, minAge, pendingWriterRegion, writerRegion string, ageHours int) (calls []string, out string) {
	t.Helper()
	bin := t.TempDir()
	callLog := filepath.Join(bin, "calls")
	modified := time.Now().UTC().Add(-time.Duration(ageHours) * time.Hour).Format("2006-01-02T15:04:05+00:00")

	arn := func(region, name string) string { return "arn:aws:rds:" + region + ":123456789012:cluster:" + name }
	members := map[string]string{
		"eu-west-2":    arn("eu-west-2", "eks-mr-abc-london-db"),
		"eu-west-3":    arn("eu-west-3", "eks-mr-abc-paris-db"),
		"eu-central-2": arn("eu-central-2", "eks-mr-abc-zurich-db"),
	}
	global := func(writer, failover string) string {
		var json []string
		for region, a := range members {
			w := "false"
			if region == writer {
				w = "true"
			}
			json = append(json, `{"DBClusterArn":"`+a+`","IsWriter":`+w+`}`)
		}
		return `{"GlobalClusterIdentifier":"eks-mr-abc-global-db",` + failover + `"GlobalClusterMembers":[` + strings.Join(json, ",") + `]}`
	}
	settled := global(writerRegion, "")
	listing := "[" + settled + "]"
	if pendingWriterRegion != "" {
		listing = "[" + global(pendingWriterRegion, `"FailoverState":{"Status":"switching-over"},`) + "]"
	}

	stub := `#!/bin/bash
echo "$*" >>"` + callLog + `"
case "$2" in
describe-global-clusters)
  if [ "$3" = --global-cluster-identifier ]; then echo '` + settled + `'; else echo '` + listing + `'; fi ;;
head-object) case "$*" in *"--key ci/tfstate-eks-mr-abc/clusters.tfstate"*) echo '` + modified + `' ;; *) exit 254 ;; esac ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "aws"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("bash", filepath.Join("..", "detach-switched-aurora-members.sh"), match, minAge)
	cmd.Env = append(os.Environ(), "PATH="+bin+":"+os.Getenv("PATH"), "TF_VAR_region_0=eu-west-2", "AURORA_POLL_SECONDS=0", "AURORA_SETTLE_SECONDS=3",
		"STATE_BUCKET=bucket", "STATE_BUCKET_REGION=eu-central-1", "STATE_PREFIX=ci/")
	o, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("the script must never fail the teardown, got %v:\n%s", err, o)
	}
	raw, _ := os.ReadFile(callLog)
	return strings.Split(strings.TrimSpace(string(raw)), "\n"), string(o)
}

// only keeps the calls of one AWS subcommand.
func only(calls []string, subcommand string) (kept []string) {
	for _, c := range calls {
		if strings.Contains(c, " "+subcommand+" ") {
			kept = append(kept, c)
		}
	}
	return kept
}

// assertDetachedLondonAndZurich checks that both readers are detached and then
// awaited, each in its own region and by its own name, and the paris writer is not.
func assertDetachedLondonAndZurich(t *testing.T, calls []string, out string) {
	t.Helper()
	removed, waited := only(calls, "remove-from-global-cluster"), only(calls, "wait")
	all := strings.Join(append(removed, waited...), "\n")
	want := []string{
		"--region eu-west-2 --global-cluster-identifier eks-mr-abc-global-db --db-cluster-identifier arn:aws:rds:eu-west-2:123456789012:cluster:eks-mr-abc-london-db",
		"--region eu-central-2 --global-cluster-identifier eks-mr-abc-global-db --db-cluster-identifier arn:aws:rds:eu-central-2:123456789012:cluster:eks-mr-abc-zurich-db",
		"db-cluster-available --region eu-west-2 --db-cluster-identifier eks-mr-abc-london-db",
		"db-cluster-available --region eu-central-2 --db-cluster-identifier eks-mr-abc-zurich-db",
	}
	for _, w := range want {
		if !strings.Contains(all, w) {
			t.Errorf("missing call %q", w)
		}
	}
	if len(removed) != 2 || len(waited) != 2 || strings.Contains(all, "paris-db") {
		t.Fatalf("expected 2 detaches and 2 waits, none for the paris writer, got:\n%s\n%s", all, out)
	}
}

func TestDetachLeavesAWriterInRegionSlotZero(t *testing.T) {
	t.Parallel()

	// Given: no failover moved the writer, so terraform destroy works as is.
	// When: the teardown preparation runs.
	calls, out := runDetach(t, "^eks-mr-abc-", "0", "eu-west-2", 1)

	// Then: no member is detached.
	if removed := only(calls, "remove-from-global-cluster"); len(removed) != 0 {
		t.Fatalf("expected no detach, got %v:\n%s", removed, out)
	}
}

func TestDetachRemovesReadersOfASwitchedWriter(t *testing.T) {
	t.Parallel()

	// Given: a failover left the writer in paris.
	// When: the teardown preparation runs.
	calls, out := runDetach(t, "^eks-mr-abc-", "0", "eu-west-3", 1)

	// Then: both readers are detached and awaited in their own regions, and the writer is not.
	assertDetachedLondonAndZurich(t, calls, out)
}

func TestDetachSkipsAClusterYoungerThanTheMinimumAge(t *testing.T) {
	t.Parallel()

	// Given: a switched writer whose Terraform state was written 3h ago, while the destroy only takes 12h and older.
	// When: the daily sweep preparation runs.
	calls, out := runDetach(t, "^eks-mr-", "12", "eu-west-3", 3)

	// Then: the stack the destroy skips is left alone.
	if removed := only(calls, "remove-from-global-cluster"); len(removed) != 0 {
		t.Fatalf("expected the young stack to be skipped, got %v:\n%s", removed, out)
	}
}

func TestDetachTakesAStackWhoseStateIsOldEnough(t *testing.T) {
	t.Parallel()

	// Given: a switched writer whose Terraform state was written 13h ago.
	// When: the daily sweep preparation runs with the destroy's 12h gate.
	calls, out := runDetach(t, "^eks-mr-", "12", "eu-west-3", 13)

	// Then: the state object the destroy gates on is read, and the readers are detached.
	if heads := only(calls, "head-object"); len(heads) != 1 || !strings.Contains(heads[0], "--bucket bucket --key ci/tfstate-eks-mr-abc/clusters.tfstate") {
		t.Fatalf("expected one read of the stack's state object, got %v:\n%s", heads, out)
	}
	assertDetachedLondonAndZurich(t, calls, out)
}

func TestDetachIgnoresOtherGlobalClusters(t *testing.T) {
	t.Parallel()

	// Given: a switched writer that belongs to another run.
	// When: the teardown preparation runs for a different cluster name.
	calls, out := runDetach(t, "^eks-mr-other-", "0", "eu-west-3", 1)

	// Then: nothing is detached.
	if removed := only(calls, "remove-from-global-cluster"); len(removed) != 0 {
		t.Fatalf("expected no detach outside the regex, got %v:\n%s", removed, out)
	}
}

func TestDetachDecidesFromTheSettledWriter(t *testing.T) {
	t.Parallel()

	// Given: a switchover to paris is still running, so the listing shows london as writer.
	// When: the teardown preparation runs.
	calls, out := runDetachSettling(t, "^eks-mr-abc-", "0", "eu-west-2", "eu-west-3", 1)

	// Then: it waits for the switchover, then detaches the readers of the settled writer in paris.
	if !strings.Contains(out, "switchover in progress") {
		t.Fatalf("expected a wait for the switchover:\n%s", out)
	}
	assertDetachedLondonAndZurich(t, calls, out)
}

func TestDetachPreparesAStackCloseToTheDestroyCutoff(t *testing.T) {
	t.Parallel()

	// Given: a switched writer whose state is 11h old, under the destroy's 12h cutoff but inside the 1h margin.
	// When: the daily sweep preparation runs.
	calls, out := runDetach(t, "^eks-mr-", "12", "eu-west-3", 11)

	// Then: it is prepared, since the destroy may reach the cutoff before it reads its own clock.
	assertDetachedLondonAndZurich(t, calls, out)
}

func TestDetachRefusesAMalformedMinimumAge(t *testing.T) {
	t.Parallel()

	// Given: a mistyped dispatch input for the age gate.
	// When: the daily sweep preparation runs with it.
	calls, out := runDetach(t, "^eks-mr-", "twelve", "eu-west-3", 1)

	// Then: nothing is read or detached, instead of skipping the gate.
	if removed := only(calls, "remove-from-global-cluster"); len(removed) != 0 || !strings.Contains(out, "must be a whole number") {
		t.Fatalf("expected the malformed age to stop the script, got %v:\n%s", removed, out)
	}
}
