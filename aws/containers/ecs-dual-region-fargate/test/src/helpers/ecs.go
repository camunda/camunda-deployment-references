// ECS service helpers — used by the failover tests to simulate a region
// outage and to assert on what failover.sh actually did to the services.
// Shells out to the AWS CLI for the same reason aurora.go does: the procedure
// scripts use the CLI, so the tests observe the system the same way an
// operator following the runbook would.
package helpers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"testing"
	"time"
)

type ecsServiceDescription struct {
	ServiceName  string `json:"serviceName"`
	DesiredCount int    `json:"desiredCount"`
	RunningCount int    `json:"runningCount"`
}

func awsJSON(t *testing.T, awsProfile string, args ...string) []byte {
	t.Helper()
	if awsProfile != "" {
		args = append(args, "--profile", awsProfile)
	}
	var stdout bytes.Buffer
	cmd := exec.Command("aws", args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stdout
	if err := cmd.Run(); err != nil {
		t.Fatalf("aws %s failed: %v\n%s", strings.Join(args, " "), err, stdout.String())
	}
	return stdout.Bytes()
}

// ecsServiceARNs lists every service ARN in a cluster.
func ecsServiceARNs(t *testing.T, awsProfile, region, cluster string) []string {
	t.Helper()
	raw := awsJSON(t, awsProfile,
		"ecs", "list-services",
		"--region", region,
		"--cluster", cluster,
		"--query", "serviceArns[]",
		"--output", "json",
	)
	var arns []string
	if err := json.Unmarshal(raw, &arns); err != nil {
		t.Fatalf("parse list-services JSON: %v\n%s", err, raw)
	}
	return arns
}

// ecsServiceDescriptions describes the given services.
//
// The ARN list is a parameter rather than being re-fetched: the drain loop
// below polls this, and the set of services cannot change while it does.
func ecsServiceDescriptions(t *testing.T, awsProfile, region, cluster string, arns []string) []ecsServiceDescription {
	t.Helper()
	out := make([]ecsServiceDescription, 0, len(arns))
	if len(arns) == 0 {
		return out
	}
	// describe-services accepts at most 10 services per call.
	for start := 0; start < len(arns); start += 10 {
		end := start + 10
		if end > len(arns) {
			end = len(arns)
		}
		args := []string{
			"ecs", "describe-services",
			"--region", region,
			"--cluster", cluster,
			"--services",
		}
		args = append(args, arns[start:end]...)
		args = append(args, "--query", "services[].{serviceName:serviceName,desiredCount:desiredCount,runningCount:runningCount}", "--output", "json")

		var descs []ecsServiceDescription
		raw := awsJSON(t, awsProfile, args...)
		if err := json.Unmarshal(raw, &descs); err != nil {
			t.Fatalf("parse describe-services JSON: %v\n%s", err, raw)
		}
		out = append(out, descs...)
	}
	return out
}

// ScaleRegionServices sets every service in a cluster to desired, and waits
// until the running count drains to match when scaling to zero.
//
// TestUnplannedFailover uses this to kill a region *before* invoking
// failover.sh, which is what "unplanned" means: the operator finds the region
// already gone rather than taking it down gracefully.
func ScaleRegionServices(t *testing.T, awsProfile, region, cluster string, desired int, timeout time.Duration) {
	t.Helper()

	arns := ecsServiceARNs(t, awsProfile, region, cluster)
	for _, arn := range arns {
		awsJSON(t, awsProfile,
			"ecs", "update-service",
			"--region", region,
			"--cluster", cluster,
			"--service", arn,
			"--desired-count", fmt.Sprintf("%d", desired),
			"--query", "service.serviceName",
			"--output", "json",
		)
		t.Logf("Scaled %s to desired-count %d", arn, desired)
	}

	if desired != 0 {
		return
	}

	// Poll on runningCount, not desiredCount: update-service already set
	// desiredCount to 0 synchronously above, so a desired-count loop would
	// exit on its first tick without observing the drain at all.
	deadline := time.Now().Add(timeout)
	for {
		running := 0
		for _, d := range ecsServiceDescriptions(t, awsProfile, region, cluster, arns) {
			running += d.RunningCount
		}
		if running == 0 {
			t.Logf("All tasks in %s (%s) have drained", cluster, region)
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("services in %s (%s) still run %d tasks after %s", cluster, region, running, timeout)
		}
		time.Sleep(15 * time.Second)
	}
}

// RequireRegionScaledDown asserts every service in the cluster sits at
// desired-count 0 — the observable outcome failover.sh guarantees.
func RequireRegionScaledDown(t *testing.T, awsProfile, region, cluster string) {
	t.Helper()
	arns := ecsServiceARNs(t, awsProfile, region, cluster)
	descs := ecsServiceDescriptions(t, awsProfile, region, cluster, arns)
	if len(descs) == 0 {
		t.Fatalf("no ECS services found in %s (%s) — cannot assert the region was scaled down", cluster, region)
	}
	for _, d := range descs {
		if d.DesiredCount != 0 {
			t.Errorf("service %s in %s still has desired-count %d, expected 0 after failover", d.ServiceName, region, d.DesiredCount)
		}
	}
}
