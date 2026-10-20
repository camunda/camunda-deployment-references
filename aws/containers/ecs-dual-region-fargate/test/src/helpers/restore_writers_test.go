package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// switchAwareMembers is a fake describe-global-clusters answer for one global
// cluster: the writer is b in region 1 until a failover-global-cluster call
// creates $FAKE_DIR/switched, then a in region 0.
const switchAwareMembers = `    if [ -f "$FAKE_DIR/switched" ]; then w=a; else w=b; fi
    echo '{"GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":'$([ $w = a ] && echo true || echo false)'},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":'$([ $w = b ] && echo true || echo false)'}]}'`

// fakeRestoreAWS serves five global clusters: one whose writer is away from
// region 0, one already home, and three that the run filter must not match
// (another run, a non-test stack, and a longer run ID ending in the same digits).
const fakeRestoreAWS = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *describe-global-clusters*--global-cluster-identifier*)
` + switchAwareMembers + ` ;;
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

// The daily cleanup restores writers in two parallel jobs: e2e-* for the
// Terratest suites and ecsdr-* for the failover lifecycle lane. At a zero age
// threshold the script skips the state-prefix lookup that otherwise keeps them
// apart, so each job's identifier filter is the only thing stopping both from
// changing one database's membership at once. The ecsdr-* case also covers the
// naming guard, which used to accept only e2e-* and so skipped the lane's
// stacks entirely.
func TestRestoreAuroraWritersJobFiltersStayDisjoint(t *testing.T) {
	t.Parallel()

	const aws = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *describe-global-clusters*--global-cluster-identifier*)
` + switchAwareMembers + ` ;;
  *describe-global-clusters*)
    echo '[
      {"GlobalClusterIdentifier":"ecsdr-3595-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]},
      {"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]},
      {"GlobalClusterIdentifier":"prod-3595-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:f","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:g","IsWriter":true}]}
    ]' ;;
  *describe-db-clusters*) echo 2000-01-01T00:00:00Z ;;
esac
`
	// The filters the two daily-cleanup jobs pass.
	for _, tc := range []struct{ job, filter, want, other string }{
		{"cleanup-clusters", "^e2e-.*-global-db$", "e2e-fo-planned-123456-global-db", "ecsdr-3595-global-db"},
		{"cleanup-lifecycle-lane", "^ecsdr-.*-global-db$", "ecsdr-3595-global-db", "e2e-fo-planned-123456-global-db"},
	} {
		t.Run(tc.job, func(t *testing.T) {
			fake := t.TempDir()
			if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), tc.filter, "0")
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
				"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0")
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("restore failed: %v\n%s", err, out)
			}
			calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
			if n := strings.Count(string(calls), "failover-global-cluster"); n != 1 ||
				!strings.Contains(string(calls), "--global-cluster-identifier "+tc.want) {
				t.Fatalf("%s: want exactly one switchover, of %s, got %d\n%s\n%s", tc.job, tc.want, n, calls, out)
			}
			// Not even read: describing it is the first step of changing its
			// membership, and the other job owns it.
			for _, id := range []string{tc.other, "prod-3595-global-db"} {
				if strings.Contains(string(calls), "--global-cluster-identifier "+id) {
					t.Fatalf("%s: touched %s, which it does not own\n%s", tc.job, id, calls)
				}
			}
		})
	}
}

// The identifier filters separate suites, not branches: main and stable
// branches both run ecsdr-<pr> lifecycle lanes, each under its own state
// prefix. A sweep given STATE_PREFIX must stay inside it even at a zero age
// threshold, which used to skip the state lookup and with it the only thing
// tying a database to a branch.
func TestRestoreAuroraWritersStaysInsideItsStatePrefix(t *testing.T) {
	t.Parallel()

	const aws = `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *list-objects-v2*"--prefix p/stable/8.10/tfstate-ecsdr-3600"*)
    echo '{"Contents":[{"Key":"p/stable/8.10/tfstate-ecsdr-3600/infra/terraform.tfstate","LastModified":"2000-01-01T00:00:00+00:00"}]}' ;;
  *list-objects-v2*) echo '{"Contents":[]}' ;;
  *describe-global-clusters*--global-cluster-identifier*)
` + switchAwareMembers + ` ;;
  *describe-global-clusters*)
    echo '[
      {"GlobalClusterIdentifier":"ecsdr-3595-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]},
      {"GlobalClusterIdentifier":"ecsdr-3600-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}
    ]' ;;
  *describe-db-clusters*) echo 2000-01-01T00:00:00Z ;;
esac
`
	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	// ecsdr-3595's states live under p/main/, ecsdr-3600's under this sweep's
	// p/stable/8.10/. Zero age, as a manual dispatch would pass.
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "^ecsdr-.*-global-db$", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0",
		"STATE_BUCKET=b", "STATE_BUCKET_REGION=eu-central-1", "STATE_PREFIX=p/stable/8.10/")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("restore failed: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if !strings.Contains(string(calls), "--global-cluster-identifier ecsdr-3600-global-db") {
		t.Fatalf("want ecsdr-3600, whose state is under the prefix, moved home\n%s\n%s", calls, out)
	}
	if strings.Contains(string(calls), "--global-cluster-identifier ecsdr-3595-global-db") {
		t.Fatalf("touched ecsdr-3595, another branch's stack\n%s\n%s", calls, out)
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
	// Every sweep here passes STATE_PREFIX=p/, as the daily cleanup does, so a
	// stack has to own a state under it to be touched at all, at any age. The
	// cases about switchover behaviour therefore list an old infra state.
	owned := `  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/infra/terraform.tfstate","LastModified":"2000-01-01T00:00:00+00:00"}]}' ;;`
	for _, tc := range []struct{ name, fake, want, minAge string }{
		{"list fails", `exit 1`, "could not list the Aurora global clusters", "0"},
		{"never settles", `case "$*" in
` + owned + `
  *--global-cluster-identifier*) echo '` + stuck + `' ;;
  *describe-global-clusters*) echo '[` + stuck + `]' ;;
esac`, "could not move the writer home", "0"},
		{"refresh fails", `case "$*" in
` + owned + `
  *--global-cluster-identifier*) exit 1 ;;
  *describe-global-clusters*) echo '[` + stuck + `]' ;;
esac`, "could not move the writer home", "0"},
		{"no infra state", `case "$*" in
  *describe-global-clusters*) echo '[` + away + `]' ;;
  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/vpc/terraform.tfstate","LastModified":"2000-01-01T00:00:00+00:00"}]}' ;;
esac`, "no readable app or infra state", "1"},
		{"fresh infra state", `case "$*" in
  *describe-global-clusters*) echo '[` + away + `]' ;;
  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/infra/terraform.tfstate","LastModified":"'$(date -u +%Y-%m-%dT%H:%M:%S+00:00)'"}]}' ;;
esac`, "state younger than 1h", "1"},
		{"fresh app state", `case "$*" in
  *describe-global-clusters*) echo '[` + away + `]' ;;
  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/infra/terraform.tfstate","LastModified":"2000-01-01T00:00:00+00:00"},{"Key":"p/tfstate-e2e-fo-planned-123456-run1/app/terraform.tfstate","LastModified":"'$(date -u +%Y-%m-%dT%H:%M:%S+00:00)'"}]}' ;;
esac`, "state younger than 1h", "1"},
		{"young stack still switching", `case "$*" in
  *describe-global-clusters*--global-cluster-identifier*) echo '` + stuck + `' ;;
  *describe-global-clusters*) echo '[` + stuck + `]' ;;
  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/infra/terraform.tfstate","LastModified":"'$(date -u +%Y-%m-%dT%H:%M:%S+00:00)'"}]}' ;;
esac`, "state younger than 1h", "1"},
		{"no home member", `case "$*" in
` + owned + `
  *) echo '[{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}]' ;;
esac`, "no member in eu-west-2", "0"},
		{"age with unit", `echo '[` + away + `]'`, "not a whole number of hours", "12h"},
		{"negative age", `echo '[` + away + `]'`, "not a whole number of hours", "-1"},
		{"oversized age", `echo '[` + away + `]'`, "not a whole number of hours", "99999999999999999999"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fake := t.TempDir()
			script := "#!/usr/bin/env bash\necho \"$*\" >> \"$FAKE_DIR/calls\"\n" + tc.fake + "\n"
			if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(script), 0o755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", tc.minAge)
			cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
				"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0", "AURORA_SETTLE_SECONDS=1",
				"STATE_BUCKET=b", "STATE_BUCKET_REGION=eu-central-1", "STATE_PREFIX=p/")
			out, err := cmd.CombinedOutput()
			calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
			if err != nil || !strings.Contains(string(out), tc.want) || strings.Contains(string(calls), "failover-global-cluster") {
				t.Fatalf("want %q and no switchover, got %v\n%s\n%s", tc.want, err, out, calls)
			}
		})
	}
}

// An age threshold is read from the state objects. Without their location the
// gate cannot run, so the sweep must stop instead of touching every stack.
func TestRestoreAuroraWritersRefusesAnAgeWithoutStatePrefix(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte("#!/usr/bin/env bash\necho \"$*\" >> \"$FAKE_DIR/calls\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "^ecsdr-.*-global-db$", "12")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "STATE_BUCKET=b", "STATE_BUCKET_REGION=eu-central-1", "STATE_PREFIX=")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "STATE_PREFIX must be set") {
		t.Fatalf("want a refusal naming STATE_PREFIX, got %v\n%s", err, out)
	}
	if calls, _ := os.ReadFile(filepath.Join(fake, "calls")); len(calls) > 0 {
		t.Fatalf("called aws before refusing\n%s", calls)
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

// A stack created with TEST_CLUSTER_PREFIX does not follow the e2e-<label>-
// naming, so the Go cleanup names its global cluster exactly instead.
func TestRestoreAuroraWritersExactIDIgnoresTheNamingGuard(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *--global-cluster-identifier\ custom-global-db\ --query*)
` + switchAwareMembers + ` ;;
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

// The daily sweep restores clusters one after the other under a step timeout.
// Once the run budget cannot fit another cluster, the script must stop and
// say so instead of being killed mid-switchover.
func TestRestoreAuroraWritersStopsAtTheRunBudget(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *describe-global-clusters*) echo '[{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}]' ;;
esac
`
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-global-db$", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake, "REGION_0=eu-west-2",
		"AURORA_WRITER_POLL_SECONDS=0", "RESTORE_BUDGET_SECONDS=60", "RESTORE_STRICT=true")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if err == nil || !strings.Contains(string(out), "run budget left") || strings.Contains(string(calls), "failover-global-cluster") {
		t.Fatalf("want no switchover and a budget error, got %v\n%s\n%s", err, calls, out)
	}
}

// An interrupted destroy can drop the region 1 cluster from the state while it
// stays in the global cluster. AWS then refuses to delete the writer's last
// instance and terraform retries until its timeout (run 37763954861). The
// writer is home here, as on a greenfield stack. Reader b has an instance and
// is detached; reader c has none, so it can be neither detached nor deleted
// (runs 37809356148, 37912265264) and is reported at once.
func TestRestoreAuroraWritersDetachesReadersOfAHomeWriter(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *describe-global-clusters*) echo '[{"GlobalClusterIdentifier":"e2e-tgw-rdbms-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":true},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:c","IsWriter":false}]}]' ;;
  *describe-db-clusters*--db-cluster-identifier\ b\ *) echo 1 ;;
  *describe-db-clusters*--db-cluster-identifier\ c\ *) echo 0 ;;
esac
`
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0", "RESTORE_STRICT=true")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	for _, want := range []string{
		"rds remove-from-global-cluster --region eu-west-3 --global-cluster-identifier e2e-tgw-rdbms-123456-global-db --db-cluster-identifier arn:aws:rds:eu-west-3:1:cluster:b",
		"rds wait db-cluster-available --region eu-west-3 --db-cluster-identifier b",
	} {
		if !strings.Contains(string(calls), want) {
			t.Fatalf("missing %q: %v\n%s\n%s", want, err, calls, out)
		}
	}
	if err == nil || !strings.Contains(string(out), "cluster:c has no instance") ||
		strings.Contains(string(calls), "failover-global-cluster") || strings.Contains(string(calls), "cluster:a --") ||
		strings.Contains(string(calls), "cluster:c --") || strings.Contains(string(calls), "delete-db-cluster") {
		t.Fatalf("want reader b detached and reader c reported, got %v\n%s\n%s", err, calls, out)
	}
}

// The age gate reads the infra state object the destroy gates on. An old
// state is restored; its exact infra key is the one read.
func TestRestoreAuroraWritersGatesOnTheInfraState(t *testing.T) {
	t.Parallel()

	fake := t.TempDir()
	aws := `#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
case "$*" in
  *failover-global-cluster*) touch "$FAKE_DIR/switched" ;;
  *describe-global-clusters*--global-cluster-identifier*)
` + switchAwareMembers + ` ;;
  *describe-global-clusters*) echo '[{"GlobalClusterIdentifier":"e2e-fo-planned-123456-global-db","GlobalClusterMembers":[{"DBClusterArn":"arn:aws:rds:eu-west-2:1:cluster:a","IsWriter":false},{"DBClusterArn":"arn:aws:rds:eu-west-3:1:cluster:b","IsWriter":true}]}]' ;;
  *list-objects-v2*) echo '{"Contents":[{"Key":"p/tfstate-e2e-fo-planned-123456-run1/infra/terraform.tfstate","LastModified":"2000-01-01T00:00:00+00:00"},{"Key":"p/tfstate-e2e-fo-planned-1234567-run1/infra/terraform.tfstate","LastModified":"2999-01-01T00:00:00+00:00"}]}' ;;
  *describe-db-clusters*) echo 1 ;;
esac
`
	if err := os.WriteFile(filepath.Join(fake, "aws"), []byte(aws), 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", filepath.Join("..", "..", "restore-aurora-writers.sh"), "-123456-global-db$", "12")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"), "FAKE_DIR="+fake,
		"REGION_0=eu-west-2", "AURORA_WRITER_POLL_SECONDS=0", "RESTORE_STRICT=true",
		"STATE_BUCKET=b", "STATE_BUCKET_REGION=eu-central-1", "STATE_PREFIX=p/")
	out, err := cmd.CombinedOutput()
	calls, _ := os.ReadFile(filepath.Join(fake, "calls"))
	if err != nil || !strings.Contains(string(calls), "list-objects-v2 --region eu-central-1 --bucket b --prefix p/tfstate-e2e-fo-planned-123456") ||
		!strings.Contains(string(calls), "failover-global-cluster --global-cluster-identifier e2e-fo-planned-123456-global-db") {
		t.Fatalf("want the old infra state read and the writer moved home, got %v\n%s\n%s", err, calls, out)
	}
}
