package helpers

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"testing"
)

// AuroraGlobalState is what a procedure claims about the Aurora Global
// Database once it reports a writer move as complete.
type AuroraGlobalState struct {
	WriterRegion  string
	FailoverState string
}

// ParseAuroraGlobal reads the `GlobalClusters[0]` object returned by
// `aws rds describe-global-clusters`.
func ParseAuroraGlobal(raw []byte) (AuroraGlobalState, error) {
	var global struct {
		FailoverState *struct {
			Status string `json:"Status"`
		} `json:"FailoverState"`
		GlobalClusterMembers []struct {
			DBClusterArn string `json:"DBClusterArn"`
			IsWriter     bool   `json:"IsWriter"`
		} `json:"GlobalClusterMembers"`
	}
	if err := json.Unmarshal(raw, &global); err != nil {
		return AuroraGlobalState{}, fmt.Errorf("parse describe-global-clusters: %w", err)
	}

	var state AuroraGlobalState
	if global.FailoverState != nil {
		state.FailoverState = global.FailoverState.Status
	}
	for _, member := range global.GlobalClusterMembers {
		if !member.IsWriter {
			continue
		}
		parts := strings.Split(member.DBClusterArn, ":")
		if len(parts) < 4 {
			return AuroraGlobalState{}, fmt.Errorf("unexpected writer ARN %q", member.DBClusterArn)
		}
		state.WriterRegion = parts[3]
	}
	if state.WriterRegion == "" {
		return AuroraGlobalState{}, fmt.Errorf("no writer member in %s", raw)
	}
	return state, nil
}

// ReadAuroraGlobal reads the global cluster once, through the AWS API endpoint
// of apiRegion. Callers use it right after a procedure returned and do not
// retry: a procedure that reports a writer move as complete must already have
// waited for it (#3572).
func ReadAuroraGlobal(t *testing.T, env Env, apiRegion string) AuroraGlobalState {
	t.Helper()

	out, err := exec.Command("aws", "rds", "describe-global-clusters",
		"--region", apiRegion,
		"--global-cluster-identifier", env.AuroraGlobalID,
		"--query", "GlobalClusters[0]", "--output", "json").Output()
	if err != nil {
		t.Fatalf("aws rds describe-global-clusters failed: %v", err)
	}
	state, err := ParseAuroraGlobal(out)
	if err != nil {
		t.Fatal(err)
	}
	return state
}
