package helpers

import (
	"encoding/json"
	"testing"
)

// /v2/topology spells roles in lowercase; a case-sensitive "LEADER" match
// counted zero leaders on a healthy cluster and timed the e2e test out.
func TestCountLeadersMatchesTopologyCasing(t *testing.T) {
	var topo Topology
	body := `{"brokers":[{"nodeId":0,"partitions":[{"partitionId":1,"role":"leader"},{"partitionId":2,"role":"follower"}]},{"nodeId":1,"partitions":[{"partitionId":2,"role":"leader"}]}]}`
	if err := json.Unmarshal([]byte(body), &topo); err != nil {
		t.Fatal(err)
	}
	if got := countLeaders(topo); got != 2 {
		t.Fatalf("countLeaders = %d, want 2", got)
	}
}

// Two leaders on one partition and none on another must not add up to a
// healthy count: only partitions with exactly one leader qualify.
func TestCountLeadersRejectsSplitBrain(t *testing.T) {
	var topo Topology
	body := `{"brokers":[{"nodeId":0,"partitions":[{"partitionId":1,"role":"leader"},{"partitionId":2,"role":"follower"}]},{"nodeId":1,"partitions":[{"partitionId":1,"role":"leader"},{"partitionId":2,"role":"follower"}]}]}`
	if err := json.Unmarshal([]byte(body), &topo); err != nil {
		t.Fatal(err)
	}
	if got := countLeaders(topo); got != 0 {
		t.Fatalf("countLeaders = %d, want 0 (partition 1 split, partition 2 leaderless)", got)
	}
}
