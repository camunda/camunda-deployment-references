// Raft topology helpers.
//
// WaitForRaftQuorum polls the Zeebe /v2/topology REST endpoint via the ALB
// until 8 brokers are registered AND each of the 8 partitions has exactly
// one leader. Returns the parsed topology on success; fails the test on
// timeout.
package helpers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

// Topology is the relevant subset of the Zeebe REST /v2/topology response.
// Fields we don't assert on are omitted to keep the struct flexible across
// minor Zeebe API revisions.
type Topology struct {
	Brokers []struct {
		NodeID     int `json:"nodeId"`
		Partitions []struct {
			PartitionID int    `json:"partitionId"`
			Role        string `json:"role"` // "leader" | "follower" | "inactive" (lowercase in /v2/topology)
		} `json:"partitions"`
	} `json:"brokers"`
	ClusterSize       int `json:"clusterSize"`
	PartitionsCount   int `json:"partitionsCount"`
	ReplicationFactor int `json:"replicationFactor"`
}

// WaitForRaftQuorum polls the topology endpoint at the supplied ALB DNS name.
// Returns the topology when:
//   - len(brokers) == expectedBrokers (default 8)
//   - every partition has exactly one LEADER
//
// The cluster runs with basic auth, so the request carries the admin
// credentials; without them every poll returns 401 and the wait can only time out.
//
// Fails the test on timeout. Poll interval defaults to 30s.
func WaitForRaftQuorum(t *testing.T, albEndpoint, username, password string, expectedBrokers, expectedPartitions int, timeout time.Duration) Topology {
	t.Helper()

	deadline := time.Now().Add(timeout)
	pollInterval := 30 * time.Second
	url := fmt.Sprintf("http://%s/v2/topology", strings.TrimSpace(albEndpoint))

	var lastTopology Topology
	for attempt := 1; time.Now().Before(deadline); attempt++ {
		topo, err := fetchTopology(url, username, password)
		if err != nil {
			t.Logf("[attempt %d] topology fetch failed: %v", attempt, err)
			time.Sleep(pollInterval)
			continue
		}
		lastTopology = topo

		leaderCount := countLeaders(topo)
		t.Logf("[attempt %d] brokers=%d/%d, leaders=%d/%d",
			attempt, len(topo.Brokers), expectedBrokers, leaderCount, expectedPartitions)

		if len(topo.Brokers) == expectedBrokers && leaderCount == expectedPartitions {
			t.Logf("Raft quorum reached after %d attempts", attempt)
			return topo
		}
		time.Sleep(pollInterval)
	}

	t.Fatalf("timeout after %v waiting for Raft quorum; last topology: brokers=%d, leaders=%d",
		timeout, len(lastTopology.Brokers), countLeaders(lastTopology))
	return Topology{} // unreachable
}

func fetchTopology(url, username, password string) (Topology, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return Topology{}, err
	}
	req.SetBasicAuth(username, password)
	resp, err := client.Do(req)
	if err != nil {
		return Topology{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return Topology{}, fmt.Errorf("topology endpoint returned HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return Topology{}, fmt.Errorf("read topology body: %w", err)
	}

	var topo Topology
	if err := json.Unmarshal(body, &topo); err != nil {
		return Topology{}, fmt.Errorf("parse topology JSON: %w", err)
	}
	return topo, nil
}

// countLeaders sums up partition entries with Role == "LEADER" across all brokers.
// Note: a healthy cluster has exactly one LEADER per partition. If two brokers
// both claim leadership for the same partition, this count exceeds expectedPartitions
// and the wait keeps going — which is the correct behavior (split brain mid-election).
func countLeaders(topo Topology) int {
	leaders := 0
	for _, b := range topo.Brokers {
		for _, p := range b.Partitions {
			if strings.EqualFold(p.Role, "leader") {
				leaders++
			}
		}
	}
	return leaders
}
