package test

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"multiregiontests/internal/helpers"
	kubectlHelpers "multiregiontests/internal/helpers/kubectl"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/stretchr/testify/require"
)

// Scaling timeout summary (retryInterval=15s):
//
//	Test                        | maxRetries | Timeout
//	Broker scaling               |         30 |  7m30s
//	Partition scaling            |        120 |    30m
//	Combined broker + partition  |        120 |    30m
//
// Tests that create new partitions need higher timeouts because Raft priority
// election (AwaitRelocationCompletion) must transfer leadership cross-region,
// which can take 15+ minutes.

// TestZeebeClusterScaleUpBrokers tests scaling Zeebe brokers in a multi-region setup
// Initial state: 8 brokers (4 per region), 8 partitions
// Target state: 12 brokers (6 per region), 8 partitions
// Reference: https://docs.camunda.io/docs/self-managed/components/orchestration-cluster/zeebe/operations/cluster-scaling/
func TestZeebeClusterScaleUpBrokers(t *testing.T) {
	t.Log("[CLUSTER SCALING TEST] Testing Zeebe broker scaling in multi-region mode 🚀")

	if globalImageTag != "" {
		t.Log("[GLOBAL IMAGE TAG] Overwriting image tag for all Camunda images with " + globalImageTag)
		baseHelmVars = helpers.OverwriteImageTag(baseHelmVars, globalImageTag)
	}

	// Runs the tests sequentially
	for _, testFuncs := range []struct {
		name  string
		tfunc func(*testing.T)
	}{
		{"TestInitKubernetesHelpers", initKubernetesHelpers},
		{"TestVerifyClusterTopology", func(t *testing.T) { verifyClusterTopology(t, 8, 8) }},
		{"TestScaleUpBrokerStatefulSets", func(t *testing.T) { scaleUpBrokerStatefulSets(t, 5) }},
		{"TestWaitForNewBrokersToStart", func(t *testing.T) { waitForNewBrokersToStart(t, 4, 1) }},
		{"TestAddNewBrokersToCluster", func(t *testing.T) { addNewBrokersToCluster(t, []int{8, 9}) }},
		{"TestWaitForBrokerScalingComplete", func(t *testing.T) { waitForScalingComplete(t, "broker scaling", 30) }},
		{"TestVerifyScaledBrokerTopology", func(t *testing.T) { verifyClusterTopology(t, 10, 8) }},
	} {
		t.Run(testFuncs.name, testFuncs.tfunc)
	}
}

// TestZeebeClusterScaleUpPartitions tests scaling partitions in a multi-region setup
// Initial state: 12 brokers (6 per region), 8 partitions
// Target state: 12 brokers (6 per region), 12 partitions
// Reference: https://docs.camunda.io/docs/self-managed/components/orchestration-cluster/zeebe/operations/cluster-scaling/
func TestZeebeClusterScaleUpPartitions(t *testing.T) {
	t.Log("[CLUSTER SCALING TEST] Testing Zeebe partition scaling in multi-region mode 🚀")

	if globalImageTag != "" {
		t.Log("[GLOBAL IMAGE TAG] Overwriting image tag for all Camunda images with " + globalImageTag)
		baseHelmVars = helpers.OverwriteImageTag(baseHelmVars, globalImageTag)
	}

	// Runs the tests sequentially
	for _, testFuncs := range []struct {
		name  string
		tfunc func(*testing.T)
	}{
		{"TestInitKubernetesHelpers", initKubernetesHelpers},
		{"TestVerifyClusterTopology", func(t *testing.T) { verifyClusterTopology(t, 10, 8) }},
		{"TestScaleUpPartitions", func(t *testing.T) { scaleUpPartitions(t, 10, 4) }},
		{"TestWaitForPartitionScalingComplete", func(t *testing.T) { waitForScalingComplete(t, "partition scaling", 120) }},
		{"TestVerifyScaledPartitionTopology", func(t *testing.T) { verifyClusterTopology(t, 10, 10) }},
	} {
		t.Run(testFuncs.name, testFuncs.tfunc)
	}
}

// TestZeebeClusterScaleUpBrokersAndPartitions tests scaling both brokers and partitions simultaneously
// Initial state: 12 brokers (6 per region), 12 partitions
// Target state: 16 brokers (8 per region), 16 partitions
// Reference: https://docs.camunda.io/docs/self-managed/components/orchestration-cluster/zeebe/operations/cluster-scaling/
func TestZeebeClusterScaleUpBothBrokersAndPartitions(t *testing.T) {
	t.Log("[CLUSTER SCALING TEST] Testing Zeebe broker and partition scaling in multi-region mode 🚀")

	if globalImageTag != "" {
		t.Log("[GLOBAL IMAGE TAG] Overwriting image tag for all Camunda images with " + globalImageTag)
		baseHelmVars = helpers.OverwriteImageTag(baseHelmVars, globalImageTag)
	}

	// Runs the tests sequentially
	for _, testFuncs := range []struct {
		name  string
		tfunc func(*testing.T)
	}{
		{"TestInitKubernetesHelpers", initKubernetesHelpers},
		{"TestVerifyClusterTopology", func(t *testing.T) { verifyClusterTopology(t, 10, 10) }},
		{"TestScaleUpBrokerStatefulSets", func(t *testing.T) { scaleUpBrokerStatefulSets(t, 6) }},
		{"TestWaitForNewBrokersToStart", func(t *testing.T) { waitForNewBrokersToStart(t, 5, 1) }},
		{"TestScaleUpBrokersAndPartitions", func(t *testing.T) { scaleUpBrokersAndPartitions(t, []int{10, 11}, 12, 4) }},
		{"TestWaitForCombinedScalingComplete", func(t *testing.T) { waitForScalingComplete(t, "combined broker and partition scaling", 120) }},
		{"TestVerifyScaledClusterTopology", func(t *testing.T) { verifyClusterTopology(t, 12, 12) }},
	} {
		t.Run(testFuncs.name, testFuncs.tfunc)
	}
}

// Helper functions for cluster scaling tests

// verifyClusterTopology verifies the cluster has the expected broker and partition counts
func verifyClusterTopology(t *testing.T, clusterSizeExpected, partitionCountExpected int) {
	t.Helper()
	t.Logf("[SCALING] Verifying cluster topology: expecting %d brokers and %d partitions 🔍", clusterSizeExpected, partitionCountExpected)

	clusterInfo := kubectlHelpers.GetClusterTopology(t, &primary.KubectlNamespace)
	require.Equal(t, clusterSizeExpected, clusterInfo.ClusterSize, "Expected %d brokers", clusterSizeExpected)
	require.Equal(t, partitionCountExpected, clusterInfo.PartitionsCount, "Expected %d partitions", partitionCountExpected)

	t.Logf("[SCALING] Topology verified: %d brokers, %d partitions, replication factor %d",
		clusterInfo.ClusterSize, clusterInfo.PartitionsCount, clusterInfo.ReplicationFactor)
}

// scaleUpBrokerStatefulSets scales the Zeebe StatefulSets via Helm upgrade by setting orchestration.clusterSize
// This approach is used when kubectl scale permissions are not available
func scaleUpBrokerStatefulSets(t *testing.T, replicasPerRegion int) {
	t.Helper()
	totalClusterSize := replicasPerRegion * 2 // Total brokers across both regions
	t.Logf("[SCALING] Scaling up Zeebe StatefulSets to %d replicas per region (%d total) via kubectl 🚀", replicasPerRegion, totalClusterSize)

	replicasArg := fmt.Sprintf("--replicas=%d", replicasPerRegion)

	t.Logf("[SCALING] Scaling primary region StatefulSet to %d replicas", replicasPerRegion)
	k8s.RunKubectl(t, &primary.KubectlNamespace, "scale", "statefulset/camunda-zeebe", replicasArg)

	t.Logf("[SCALING] Scaling secondary region StatefulSet to %d replicas", replicasPerRegion)
	k8s.RunKubectl(t, &secondary.KubectlNamespace, "scale", "statefulset/camunda-zeebe", replicasArg)

	t.Log("[SCALING] Helm upgrades completed, StatefulSets will scale up")
}

// waitForNewBrokersToStart waits for the new broker pods to have status=Running
// startIndex is the first new pod index, count is how many new pods to wait for
func waitForNewBrokersToStart(t *testing.T, startIndex, count int) {
	t.Helper()
	t.Logf("[SCALING] Waiting for %d new broker pods starting at index %d to be Running 🕐", count, startIndex)

	for i := startIndex; i < startIndex+count; i++ {
		podName := fmt.Sprintf("camunda-zeebe-%d", i)
		waitForPodRunning(t, &primary.KubectlNamespace, podName, "primary")
		waitForPodRunning(t, &secondary.KubectlNamespace, podName, "secondary")
	}

	t.Log("[SCALING] All new broker pods are Running")
}

// waitForPodRunning waits for a specific pod to reach Running status
func waitForPodRunning(t *testing.T, kubectlOptions *k8s.KubectlOptions, podName, regionName string) {
	t.Helper()

	maxRetries := 20
	retryInterval := 15 * time.Second

	t.Logf("[SCALING] Waiting for %s region pod %s to be Running", regionName, podName)
	for retry := 0; retry < maxRetries; retry++ {
		phase, err := k8s.RunKubectlAndGetOutputE(t, kubectlOptions, "get", "pod", podName, "-o", "jsonpath={.status.phase}", "--request-timeout=30s")
		if err == nil && phase == "Running" {
			t.Logf("[SCALING] %s region pod %s is Running", regionName, podName)
			return
		}
		if retry == maxRetries-1 {
			t.Fatalf("[SCALING] %s region pod %s did not reach Running status (current: %q, err: %v)", regionName, podName, phase, err)
		}
		t.Logf("[SCALING] %s region pod %s status: %q (attempt %d/%d)", regionName, podName, phase, retry+1, maxRetries)
		time.Sleep(retryInterval)
	}
}

// waitForScalingComplete polls the cluster status until scaling is complete
// operationName is used for logging, maxRetries controls the timeout (each retry waits 15 seconds)
func waitForScalingComplete(t *testing.T, operationName string, maxRetries int) {
	t.Helper()
	t.Logf("[SCALING] Waiting for %s to complete 🕐", operationName)

	// Poll the gateway cluster topology until the scaling change is no longer pending,
	// tolerating transient connection drops and self-healing any broker that hangs on
	// the cross-region clusterset-DNS race during a restart (camunda/camunda#55038),
	// which would otherwise stall the redistribution forever. Each request uses its own
	// short-lived kubectl port-forward (see GatewayManagementRequest).
	notReadySince := map[string]time.Time{}
	brokerRestarts := 0
	completed := false
	var lastBody string
	for i := 0; i < maxRetries; i++ {
		status, body, err := kubectlHelpers.GatewayManagementRequest(t, &primary.KubectlNamespace, "GET", "/actuator/cluster", nil)
		if err == nil && status == 200 {
			lastBody = body
			// Check if there's no pending change
			if !strings.Contains(body, "pendingChange") {
				t.Logf("[SCALING] %s completed successfully", operationName)
				require.Contains(t, body, "COMPLETED", "Expected lastChange status to be COMPLETED")
				completed = true
				break
			}
			t.Logf("[SCALING] %s in progress... (attempt %d/%d)", operationName, i+1, maxRetries)
		} else if err != nil {
			t.Logf("[SCALING] %s status request failed (attempt %d/%d), retrying: %v", operationName, i+1, maxRetries, err)
		} else {
			t.Logf("[SCALING] %s unexpected status %d (attempt %d/%d), retrying", operationName, status, i+1, maxRetries)
		}

		// Self-heal a broker left Running-but-not-Ready on the clusterset-DNS race so
		// the scaling change can progress; heal at most one region per iteration.
		if kubectlHelpers.SelfHealStuckBrokers(t, &secondary.KubectlNamespace, "camunda-zeebe", notReadySince, &brokerRestarts, 90*time.Second, 6) == 0 {
			kubectlHelpers.SelfHealStuckBrokers(t, &primary.KubectlNamespace, "camunda-zeebe", notReadySince, &brokerRestarts, 90*time.Second, 6)
		}
		time.Sleep(15 * time.Second)
	}

	require.True(t, completed, "[SCALING] %s did not complete within the expected time (last status body: %s)", operationName, lastBody)
}

// addNewBrokersToCluster sends API request to add new brokers to the cluster
func addNewBrokersToCluster(t *testing.T, brokersToAdd []int) {
	t.Helper()
	t.Logf("[SCALING] Adding new brokers %v to the cluster via API 🚀", brokersToAdd)

	payload := map[string]interface{}{
		"brokers": map[string]interface{}{
			"add": brokersToAdd,
		},
	}
	patchClusterTopology(t, payload, "broker addition")
}

// scaleUpPartitions sends API request to increase partition count
func scaleUpPartitions(t *testing.T, partitionCount, replicationFactor int) {
	t.Helper()
	t.Logf("[SCALING] Scaling up to %d partitions with replication factor %d 🚀", partitionCount, replicationFactor)

	payload := map[string]interface{}{
		"partitions": map[string]interface{}{
			"count":             partitionCount,
			"replicationFactor": replicationFactor,
		},
	}
	patchClusterTopology(t, payload, "partition scaling")
}

// scaleUpBrokersAndPartitions sends API request to scale both brokers and partitions
func scaleUpBrokersAndPartitions(t *testing.T, brokersToAdd []int, partitionCount, replicationFactor int) {
	t.Helper()
	t.Logf("[SCALING] Scaling up brokers %v and partitions to %d simultaneously 🚀", brokersToAdd, partitionCount)

	payload := map[string]interface{}{
		"brokers": map[string]interface{}{
			"add": brokersToAdd,
		},
		"partitions": map[string]interface{}{
			"count":             partitionCount,
			"replicationFactor": replicationFactor,
		},
	}
	patchClusterTopology(t, payload, "combined broker and partition scaling")
}

// patchClusterTopology sends a PATCH request to the Zeebe gateway cluster actuator endpoint
// It performs a dry run first, then executes the actual scaling operation
func patchClusterTopology(t *testing.T, payload map[string]interface{}, operationName string) {
	t.Helper()

	payloadBytes, err := json.Marshal(payload)
	require.NoError(t, err, "Failed to marshal payload")

	// Issue the scaling change through the gateway, retrying on transient 5xx (the
	// gateway can briefly reject a mutating request while partitions redistribute).
	// The request uses a short-lived kubectl port-forward (see GatewayManagementMutate).
	t.Logf("[SCALING] Executing %s", operationName)
	status, body, err := kubectlHelpers.GatewayManagementMutate(t, &primary.KubectlNamespace, "PATCH", "/actuator/cluster", payloadBytes, 8, 15*time.Second)
	require.NoError(t, err, "Failed to request %s", operationName)
	require.Equal(t, 202, status, "Expected 202 Accepted status")
	require.NotEmpty(t, body)
	require.Contains(t, body, "plannedChanges")
	require.Contains(t, body, "changeId")

	// Parse and log the change ID
	var response map[string]interface{}
	err = json.Unmarshal([]byte(body), &response)
	require.NoError(t, err)
	changeId := response["changeId"]
	t.Logf("[SCALING] %s initiated with changeId: %v", operationName, changeId)
}
