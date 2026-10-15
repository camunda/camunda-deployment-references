package helpers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const (
	london = "arn:aws:rds:eu-west-2:1:cluster:london"
	paris  = "arn:aws:rds:eu-west-3:1:cluster:paris"
)

func TestParseAuroraGlobal(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name, raw, writer, failover string
	}{
		{"settled", `{"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":false},{"DBClusterArn":"` + paris + `","IsWriter":true}]}`, "eu-west-3", ""},
		{"switching", `{"FailoverState":{"Status":"switching-over"},"GlobalClusterMembers":[{"DBClusterArn":"` + london + `","IsWriter":true}]}`, "eu-west-2", "switching-over"},
	}
	for _, c := range cases {
		got, err := ParseAuroraGlobal([]byte(c.raw))
		if err != nil || got.WriterRegion != c.writer || got.FailoverState != c.failover {
			t.Errorf("%s: got %+v, %v", c.name, got, err)
		}
	}

	// The AWS field is IsWriter; IsClusterWriter does not exist and must not
	// silently count as a writer.
	if _, err := ParseAuroraGlobal([]byte(`{"GlobalClusterMembers":[{"DBClusterArn":"` + paris + `","IsClusterWriter":true}]}`)); err == nil {
		t.Error("IsClusterWriter was accepted as the writer flag")
	}
}

// The wait, settle and switchover helpers live in procedure/aurora.sh, which
// is identical to the ECS dual-region copy. Their offline tests are in
// aws/containers/ecs-dual-region-fargate/test/src/helpers/aurora_test.go,
// which also checks that both copies match.

func TestFailoverRejectsMissingWriter(t *testing.T) {
	t.Parallel()
	// Given: an empty global membership and an offline management API.
	fake := t.TempDir()
	body, err := os.ReadFile(filepath.Join(ProcedureDir(t), "failover.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{
		"failover.sh": string(body),
		"lib-management-api.sh": `camunda::require_slot() { :; }
camunda::survivor_context() { echo survivor; }
camunda::use_surviving_region() { :; }
camunda::management() { echo '{}'; }
`,
		"aurora.sh": `aurora_settled_global() { echo '{"GlobalClusterMembers":[]}'; }
aurora_switch_to() { :; }
`,
		"aws": "#!/usr/bin/env bash\necho '[]'\n",
	} {
		if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command("bash", filepath.Join(fake, "failover.sh"), "0", "--dry-run")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"),
		"CLUSTER_CONTEXTS=a b c", "AWS_REGIONS=eu-west-2 eu-west-3 eu-central-1",
		"CAMUNDA_ACTIVE_REGIONS=3", "CAMUNDA_REGION_SLOTS=3", "CAMUNDA_BROKERS_PER_REGION=2",
		"CAMUNDA_ZONE_REPLICAS=2 2 1", "CAMUNDA_REPLICATION_FACTOR=5", "AURORA_GLOBAL_CLUSTER_ID=g")
	// When
	out, err := cmd.CombinedOutput()
	// Then
	if err == nil || !strings.Contains(string(out), "No Aurora writer ARN") {
		t.Fatalf("expected a missing-writer error, got %v\n%s", err, out)
	}
}

// #3678: a failed AWS read is not a broken global database. failback.sh must
// show the AWS error, not send the operator to unplanned recovery.
func TestFailbackReportsAWSReadErrors(t *testing.T) {
	t.Parallel()
	// Given: a zone that was never removed and an AWS CLI with expired credentials.
	fake := t.TempDir()
	body, err := os.ReadFile(filepath.Join(ProcedureDir(t), "failback.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(fake, "submariner"), 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"failback.sh": string(body),
		"lib-management-api.sh": `camunda::require_slot() { :; }
camunda::survivor_context() { echo survivor; }
camunda::use_surviving_region() { :; }
camunda::zone_name() { echo z; }
camunda::management() { echo '{}'; }
camunda::partitioning() { echo '{"zones":[{"name":"z"}]}'; }
`,
		"aurora.sh":                     "",
		"generate-zeebe-helm-values.sh": "",
		"aws":                           "#!/usr/bin/env bash\necho 'An error occurred (ExpiredTokenException): token expired' >&2\nexit 254\n",
	}
	for _, stub := range []string{"setup-namespaces.sh", "create-rdbms-secret.sh", "assemble-envsubst-values.sh",
		"install-chart.sh", "submariner/export-services.sh", "check-cluster-topology.sh"} {
		files[stub] = "#!/usr/bin/env bash\n"
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(fake, name), []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command("bash", filepath.Join(fake, "failback.sh"), "0")
	cmd.Env = append(os.Environ(), "PATH="+fake+":"+os.Getenv("PATH"),
		"CLUSTER_CONTEXTS=a b c", "AWS_REGIONS=eu-west-2 eu-west-3 eu-central-1",
		"CAMUNDA_ACTIVE_REGIONS=3", "CAMUNDA_REGION_SLOTS=3", "CAMUNDA_BROKERS_PER_REGION=2",
		"AURORA_GLOBAL_CLUSTER_ID=g")
	// When
	out, err := cmd.CombinedOutput()
	// Then
	if err == nil || !strings.Contains(string(out), "ExpiredTokenException") || strings.Contains(string(out), "unplanned-recovery") {
		t.Fatalf("want the AWS error, got %v\n%s", err, out)
	}
}
