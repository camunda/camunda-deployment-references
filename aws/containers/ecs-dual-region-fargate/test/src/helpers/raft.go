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
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// AdminPassword reads the infra/ output admin_user_password without logging
// it: terratest logs every command's output by default. In GitHub Actions the
// value is also masked, since the procedures print it in their hints.
func AdminPassword(t *testing.T, infraOpts *terraform.Options) string {
	t.Helper()

	quiet := *infraOpts
	quiet.Logger = logger.Discard
	password := terraform.Output(t, &quiet, "admin_user_password")
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		fmt.Printf("::add-mask::%s\n", password)
	}
	return password
}

// Topology is the relevant subset of the Zeebe REST /v2/topology response.
// Fields we don't assert on are omitted to keep the struct flexible across
// minor Zeebe API revisions.
type Topology struct {
	Brokers []struct {
		NodeID     int `json:"nodeId"`
		Partitions []struct {
			PartitionID int    `json:"partitionId"`
			Role        string `json:"role"` // "leader" | "follower" | "inactive"
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
//
// The endpoint requires basic auth: adminPassword is the infra/ output
// admin_user_password, for the "admin" user.
func WaitForRaftQuorum(t *testing.T, albEndpoint, adminPassword string, expectedBrokers, expectedPartitions int, timeout time.Duration) Topology {
	t.Helper()

	deadline := time.Now().Add(timeout)
	pollInterval := 30 * time.Second
	url := fmt.Sprintf("http://%s/v2/topology", strings.TrimSpace(albEndpoint))

	var lastTopology Topology
	for attempt := 1; time.Now().Before(deadline); attempt++ {
		topo, err := fetchTopology(url, adminPassword)
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

func fetchTopology(url, adminPassword string) (Topology, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return Topology{}, err
	}
	req.SetBasicAuth("admin", adminPassword)
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

// countLeaders returns how many partitions have exactly one leader. A summed
// leader count can reach the expected total with one partition led twice and
// another not led at all.
func countLeaders(topo Topology) int {
	perPartition := map[int]int{}
	for _, b := range topo.Brokers {
		for _, p := range b.Partitions {
			if strings.EqualFold(p.Role, "leader") {
				perPartition[p.PartitionID]++
			}
		}
	}
	settled := 0
	for _, n := range perPartition {
		if n == 1 {
			settled++
		}
	}
	return settled
}
