package helpers

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

// WaitForPartitionLeaders polls the topology until every partition has exactly
// one leader, and returns the topology it saw.
//
// Unlike WaitForRaftQuorum it makes no claim about the broker count, because
// after a zone removal that number says nothing useful: the scaled-down
// region's brokers stay in cluster membership for a while, hosting zero
// replicas. A live failover showed `brokers=8, clusterSize=4,
// replicationFactor=2` immediately afterwards — waiting for the count to fall
// to 4 waits on ECS task teardown, not on anything about the cluster's health.
//
// Re-election is also not instantaneous: the same run had 5 of 8 partitions
// led the moment the cluster change completed, with the rest following inside
// a minute. The replication factor is the assertion that proves the zone left
// the distribution; this one proves the survivors are serving.
func WaitForPartitionLeaders(t *testing.T, albEndpoint, username, password string, expectedPartitions int, timeout time.Duration) Topology {
	t.Helper()

	deadline := time.Now().Add(timeout)
	pollInterval := 15 * time.Second
	url := fmt.Sprintf("http://%s/v2/topology", strings.TrimSpace(albEndpoint))

	var last Topology
	for attempt := 1; time.Now().Before(deadline); attempt++ {
		topo, err := fetchTopology(url, username, password)
		if err != nil {
			t.Logf("[attempt %d] topology fetch failed: %v", attempt, err)
			time.Sleep(pollInterval)
			continue
		}
		last = topo

		led := countLeaders(topo)
		t.Logf("[attempt %d] partitions led=%d/%d, brokers=%d, replicationFactor=%d",
			attempt, led, expectedPartitions, len(topo.Brokers), topo.ReplicationFactor)

		if led == expectedPartitions {
			t.Logf("Every partition has a leader after %d attempts", attempt)
			return topo
		}
		time.Sleep(pollInterval)
	}

	t.Fatalf("timeout after %v waiting for every partition to have a leader; last saw %d/%d led",
		timeout, countLeaders(last), expectedPartitions)
	return Topology{} // unreachable
}
