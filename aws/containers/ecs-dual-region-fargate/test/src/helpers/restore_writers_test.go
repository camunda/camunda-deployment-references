package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeRestoreAWS serves five global clusters: one whose writer is away from
// region 0, one already home, and three that the run filter must not match
// (another run, a non-test stack, and a longer run ID ending in the same digits).
const fakeRestoreAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *describe-global-clusters*--global-cluster-identifier*)
    echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}' ;;
  *describe-global-clusters*)
    echo '[
      {"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fb-switch-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:c","IsWriter":true}]},
      {"GlobalClusterIdentifier":"prod-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:f","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:g","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fo-planned-9123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:h","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:i","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fo-planned-999999-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:d","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:e","IsWriter":true}]}
    ]' ;;
  *describe-db-clusters*) echo 2000-01-01T00:00:00Z ;;
esac
`

func TestRestoreAuroraWritersMovesOnlyMatchingStrayWriters(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeRestoreAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("restore failed: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	switches := strings.Count(string(calls), "failover-global-cluster")
	if switches != 1 || !strings.Contains(string(calls),
		"failover-global-cluster --global-cluster-identifier e2e-fo-planned-123456-global-db --target-db-cluster-identifier arn:aws:rds:eu-west-2:1:cluster:a") {
		t.Fatalf("want one switchover of e2e-fo-planned-123456 to region 0, got %d\n%s\n%s", switches, calls, out)
	}
}

// fakeSettlingAWS lists one global cluster whose region-0 member is still
// flagged writer while a switchover to region 1 runs. Once FailoverState
// clears, the writer is in region 1 and must be moved home.
const fakeSettlingAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
n=$(grep -c describe-global-clusters "$FAKE_DIR/calls")
case "$*" in
  *describe-global-clusters*)
    if [ "$n" -le 2 ]; then
      m='{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'
    elif [ -f "$FAKE_DIR/switched" ]; then
      m='{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false}]}'
    else
      m='{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}'
    fi
    case "$*" in *--global-cluster-identifier*) echo "$m" ;; *) echo "[$m]" ;; esac ;;
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *describe-db-clusters*) echo 2000-01-01T00:00:00Z ;;
esac
`

func TestRestoreAuroraWritersWaitsForARunningSwitchover(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(fakeSettlingAWS), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if err != nil || !strings.Contains(string(calls), "failover-global-cluster") {
		t.Fatalf("did not move the writer home after the switchover settled: %v\n%s\n%s", err, calls, out)
	}
}

func TestRestoreAuroraWritersSkipsWhatItCannotRead(t *testing.T) {
	t.Parallel()

	stuck := `{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}`
	away := `{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}`
	for _, tc := range []struct{ name, fake, want, minAge string }{
		{"list fails", `exit 1`, "could not list the Aurora global clusters", "0"},
		{"never settles", `case "$*" in
  *--global-cluster-identifier*) echo '` + stuck + `' ;;
  *describe-global-clusters*) echo '[` + stuck + `]' ;;
esac`, "still switching over", "0"},
		{"refresh fails", `case "$*" in
  *--global-cluster-identifier*) exit 1 ;;
  *describe-global-clusters*) echo '[` + stuck + `]' ;;
esac`, "still switching over", "0"},
		{"age unknown", `case "$*" in
  *describe-global-clusters*) echo '[` + away + `]' ;;
  *describe-db-clusters*) exit 1 ;;
esac`, "could not read the creation time", "1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fake := t.TempDir()
			script := "#!/usr/bin/env bash\necho \"$*\" >> \"$FAKE_DIR/calls\"\n" + tc.fake + "\n"
			if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(script), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", tc.minAge)
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
				"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0", "AURORA_SETTLE_SECONDS=1")
			out, err := cmd.CombinedOutput()
			calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
			if err != nil || !strings.Contains(string(out), tc.want) || strings.Contains(string(calls), "failover-global-cluster") {
				t.Fatalf("want %q and no switchover, got %v\n%s\n%s", tc.want, err, out, calls)
			}
		})
	}
}

func TestRestoreAuroraWritersStrictModeReportsFailures(t *testing.T) {
	t.Parallel()

	stuck := `{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}`
	for name, fake := range map[string]string{
		"list fails":    `exit 1`,
		"never settles": `case "$*" in *--global-cluster-identifier*) echo '` + stuck + `' ;; *) echo '[` + stuck + `]' ;; esac`,
	} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "aws"), []byte("#!/usr/bin/env bash\n"+fake+"\n"), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", "0")
			cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"), "REGION_0=eu-west-2",
				"AURORA_WRITER_POLL_SECONDS=0", "AURORA_SETTLE_SECONDS=1", "RESTORE_STRICT=true")
			if out, err := cmd.CombinedOutput(); err == nil {
				t.Fatalf("strict mode exited 0 after a failed restore\n%s", out)
			}
		})
	}
}

// A stack created with TEST_CLUSTER_PREFIX does not follow the e2e-f[ob]-
// naming, so the Go cleanup names its global cluster exactly instead.
func TestRestoreAuroraWritersExactIDIgnoresTheNamingGuard(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *--global-cluster-identifier\ custom-global-db\ --query*) echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true}]}' ;;
  *describe-global-clusters*) echo '[{"GlobalClusterIdentifier":"custom-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}]' ;;
esac
`
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "custom-global-db", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0", "RESTORE_EXACT_ID=true", "RESTORE_STRICT=true")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if err != nil || !strings.Contains(string(calls), "failover-global-cluster --global-cluster-identifier custom-global-db") {
		t.Fatalf("exact ID was not restored: %v\n%s\n%s", err, calls, out)
	}
}

// Right after a switchover AWS refuses the next one with "replication setup
// is still in progress. Please retry". Seen on the failover suite: the
// pre-destroy restore gave up, and destroy then hung with the writer away.
func TestRestoreAuroraWritersRetriesWhileReplicationSetsUp(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*)
    n=$(grep -c failover-global-cluster "$FAKE_DIR/calls")
    if [ "$n" -le 2 ]; then
      echo "An error occurred (InvalidDBClusterStateFault) when calling the FailoverGlobalCluster operation: The switchover request is not successful because replication setup is still in progress. Please retry the request later." >&2
      exit 254
    fi
    touch "$FAKE_DIR/switched" ;;
  *describe-global-clusters*--global-cluster-identifier*)
    if [ -f "$FAKE_DIR/switched" ]; then w=a; else w=b; fi
    echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":'$([ $w = a ] && echo true || echo false)'},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":'$([ $w = b ] && echo true || echo false)'}]}' ;;
  *describe-global-clusters*)
    echo '[{"GlobalClusterIdentifier":"g","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}]' ;;
esac
`
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "g", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake, "REGION_0=eu-west-2",
		"AURORA_WRITER_POLL_SECONDS=0", "RESTORE_EXACT_ID=true", "RESTORE_STRICT=true")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if err != nil || strings.Count(string(calls), "failover-global-cluster") != 3 {
		t.Fatalf("want 3 switchover attempts and success, got %v\n%s\n%s", err, calls, out)
	}
}
