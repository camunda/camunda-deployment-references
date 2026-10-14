package helpers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// The orchestration cluster's /v2/topology requires basic auth and reports
// roles in lower case, as the procedures' `select(.role == "leader")` expects.
func TestWaitForRaftQuorumAuthenticatesAndCountsLeaders(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if user, pass, ok := r.BasicAuth(); !ok || user != "admin" || pass != "secret" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`{"brokers":[
			{"nodeId":0,"partitions":[{"partitionId":1,"role":"leader"},{"partitionId":2,"role":"follower"}]},
			{"nodeId":1,"partitions":[{"partitionId":1,"role":"follower"},{"partitionId":2,"role":"leader"}]}]}`))
	}))
	defer server.Close()

	topo := WaitForRaftQuorum(t, strings.TrimPrefix(server.URL, "http://"), "secret", 2, 2, time.Second)
	if len(topo.Brokers) != 2 {
		t.Fatalf("got %d brokers, want 2", len(topo.Brokers))
	}
}

// Two leaders for partition 1 and none for partition 2 add up to the
// expected count, but partition 2 has no quorum.
func TestCountLeadersNeedsOneLeaderPerPartition(t *testing.T) {
	t.Parallel()

	var topo Topology
	raw := `{"brokers":[
		{"nodeId":0,"partitions":[{"partitionId":1,"role":"leader"},{"partitionId":2,"role":"follower"}]},
		{"nodeId":1,"partitions":[{"partitionId":1,"role":"LEADER"},{"partitionId":2,"role":"follower"}]}]}`
	if err := json.Unmarshal([]byte(raw), &topo); err != nil {
		t.Fatal(err)
	}
	if got := countLeaders(topo); got != 0 {
		t.Fatalf("countLeaders = %d, want 0 partitions with exactly one leader", got)
	}
}
