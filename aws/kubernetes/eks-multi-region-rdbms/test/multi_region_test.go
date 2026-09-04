// Integration tests for the AWS EKS multi-region RDBMS reference architecture.
//
// The suite is written as a sequence of independently runnable tests so that a
// failure can be resumed without recreating the whole infrastructure, which
// takes about 40 minutes. CI runs them in the order below; locally, run the one
// you care about after the environment exists.
//
//	TestMultiRegionKubeConfig       register kubectl contexts
//	TestMultiRegionSubmariner       build the ClusterSet mesh
//	TestMultiRegionDeployCamunda    install Camunda in every active region
//	TestMultiRegionTopology         assert the expected broker distribution
//	TestMultiRegionRdbmsLatency     measure the write path to the single writer
//	TestMultiRegionActivateRegion   grow the cluster by one region, online
//	TestMultiRegionRegionLoss       remove a region and verify quorum
//	TestMultiRegionDrainZone        force-remove the lost zone
//	TestMultiRegionFailback         bring the region back
//	TestMultiRegionCleanup          uninstall Camunda
//
// Infrastructure lifecycle (terraform apply and destroy) is intentionally NOT
// part of the suite: it is driven by the reusable CI actions so that a failed
// test run still hits the same teardown path as every other reference
// architecture.
package multiregionrdbmstests

import (
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"multiregionrdbmstests/helpers"
)

const terraformDir = "../terraform/clusters"

func testEnv(t *testing.T) helpers.Env {
	t.Helper()

	outputs := helpers.ReadTerraformOutputs(t, terraformDir)

	contexts := splitList(helpers.GetEnv("CLUSTER_CONTEXTS", ""))
	if len(contexts) == 0 {
		// Default aliases mirror the region short names, which is what
		// export-terraform-outputs.sh produces.
		for _, short := range outputs.ShortNames {
			contexts = append(contexts, "cluster-"+short)
		}
	}

	activeRegions := outputs.ActiveRegionCount
	if v := os.Getenv("CAMUNDA_ACTIVE_REGIONS"); v != "" {
		parsed, err := strconv.Atoi(v)
		if err != nil {
			t.Fatalf("CAMUNDA_ACTIVE_REGIONS is not a number: %v", err)
		}
		activeRegions = parsed
	}

	brokersPerRegion, err := strconv.Atoi(helpers.GetEnv("CAMUNDA_BROKERS_PER_REGION", "2"))
	if err != nil {
		t.Fatalf("CAMUNDA_BROKERS_PER_REGION is not a number: %v", err)
	}

	return helpers.Env{
		RegionSlots:        outputs.RegionSlotCount,
		ActiveRegions:      activeRegions,
		BrokersPerRegion:   brokersPerRegion,
		ClusterContexts:    contexts,
		AWSRegions:         outputs.AWSRegions,
		SubmarinerClusters: outputs.ShortNames,
		ZoneNames:          outputs.ZoneNames,
		ClusterNames:       outputs.ClusterNames,
		VPCCidrBlocks:      outputs.VPCCidrBlocks,
		ServiceCidrBlocks:  outputs.ServiceCidrBlocks,
		// Any cluster can host the Submariner broker; it only stores metadata.
		SubmarinerBrokerSlot: 0,
		Namespace:            helpers.GetEnv("CAMUNDA_NAMESPACE", "camunda"),
		ReleaseName:          helpers.GetEnv("CAMUNDA_RELEASE_NAME", "camunda"),
		RdbmsURL:             outputs.RdbmsURL,
		RdbmsUsername:        outputs.RdbmsUsername,
		RdbmsPassword:        outputs.RdbmsPassword,
		AuroraGlobalID:       outputs.AuroraGlobalID,
	}
}

func splitList(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return strings.Fields(value)
}

// TestMultiRegionKubeConfig registers one kubectl context per active region.
func TestMultiRegionKubeConfig(t *testing.T) {
	env := testEnv(t)
	outputs := helpers.ReadTerraformOutputs(t, terraformDir)
	helpers.UpdateKubeConfig(t, outputs, env.ClusterContexts)
}

// TestMultiRegionSubmariner builds the Submariner ClusterSet, asserts that
// service discovery is functional in every cluster, and then proves that the
// Transit Gateway actually carries pod-to-pod traffic between regions.
func TestMultiRegionSubmariner(t *testing.T) {
	env := testEnv(t)

	helpers.RunProcedure(t, env, 10*time.Minute, "storageclass-configure.sh")
	helpers.RunProcedure(t, env, 2*time.Minute, "storageclass-verify.sh")

	helpers.RunProcedure(t, env, 10*time.Minute, "submariner/deploy-broker.sh")
	helpers.RunProcedure(t, env, 20*time.Minute, "submariner/join-clusters.sh")
	helpers.RunProcedure(t, env, 20*time.Minute, "submariner/verify-submariner.sh")

	// Proves the substrate in about two minutes, before the twenty-five the
	// Camunda install costs. Submariner reporting healthy says nothing about
	// reachability here -- it does not carry the traffic -- so this is the only
	// check that covers the Transit Gateway routes and the firewall rules.
	helpers.RunProcedure(t, env, 10*time.Minute, "setup-namespaces.sh")
	helpers.RunProcedure(t, env, 15*time.Minute, "verify-cross-region-connectivity.sh")
}

// TestMultiRegionDeployCamunda installs Camunda in every active region.
func TestMultiRegionDeployCamunda(t *testing.T) {
	env := testEnv(t)

	if env.RdbmsURL == "" {
		t.Fatal("terraform output camunda_rdbms_url is empty; the database is required for this architecture")
	}

	helpers.RunProcedure(t, env, 5*time.Minute, "setup-namespaces.sh")
	helpers.RunProcedure(t, env, 5*time.Minute, "create-rdbms-secret.sh")
	helpers.RunProcedure(t, env, 30*time.Minute, "deploy.sh")
	helpers.RunProcedure(t, env, 15*time.Minute, "submariner/export-services.sh")
}

// TestMultiRegionTopology asserts the multi-region broker distribution:
// clusterSize brokers, one replica of every partition per region, no unhealthy
// partition.
func TestMultiRegionTopology(t *testing.T) {
	env := testEnv(t)

	defer helpers.RunProcedureAllowFailure(t, env, 5*time.Minute, "submariner/diagnose-submariner.sh")
	helpers.RunProcedure(t, env, 30*time.Minute, "check-cluster-topology.sh")
}

// TestMultiRegionRdbmsLatency measures the cost of the active-standby database
// tier: every region exports to one writer, so a region that does not host it
// pays the inter-region round trip on every flush.
//
// It is a measurement, not an assertion. There is no threshold to fail on --
// the acceptable latency depends on the region pair and on the configured
// queue size -- but the number belongs in the run log, because it is the main
// input for sizing orchestration.data.secondaryStorage.rdbms.queueSize and it
// has never been captured for this architecture.
func TestMultiRegionRdbmsLatency(t *testing.T) {
	env := testEnv(t)

	if env.RdbmsURL == "" {
		t.Skip("terraform output camunda_rdbms_url is empty; nothing to measure")
	}

	helpers.RunProcedureAllowFailure(t, env, 15*time.Minute, "measure-rdbms-latency.sh")
}

// TestMultiRegionActivateRegion grows the cluster by one region while it is
// serving traffic. It only runs when the infrastructure was bootstrapped with a
// spare region slot, which is the growth scenario described in the README.
func TestMultiRegionActivateRegion(t *testing.T) {
	env := testEnv(t)

	if env.ActiveRegions >= env.RegionSlots {
		t.Skipf("every region slot is already active (%d/%d), nothing to activate",
			env.ActiveRegions, env.RegionSlots)
	}

	slot := env.ActiveRegions
	env.ActiveRegions = slot + 1

	defer helpers.RunProcedureAllowFailure(t, env, 5*time.Minute, "submariner/diagnose-submariner.sh")
	helpers.RunProcedure(t, env, 45*time.Minute, "activate-region.sh", strconv.Itoa(slot))
}

// TestMultiRegionRegionLoss simulates the loss of one region and asserts that
// the workflow engine keeps its quorum. This is the property the whole
// architecture exists for, and the one that distinguishes it from the
// dual-region setup, where the same event halts processing.
func TestMultiRegionRegionLoss(t *testing.T) {
	env := testEnv(t)

	if env.ActiveRegions < 3 {
		t.Skipf("need at least 3 active regions to survive a region loss, have %d", env.ActiveRegions)
	}

	// Slot 0 hosts the Aurora writer. Losing it exercises the database switchover
	// as well as Zeebe quorum; the management API is driven from a survivor.
	lostSlot := 0

	defer helpers.RunProcedureAllowFailure(t, env, 5*time.Minute, "submariner/diagnose-submariner.sh")

	helpers.RunProcedure(t, env, 15*time.Minute, "simulate-region-loss.sh", strconv.Itoa(lostSlot))
	helpers.RunProcedure(t, env, 15*time.Minute, "verify-degraded-cluster.sh", strconv.Itoa(lostSlot))
}

// TestMultiRegionDrainZone force-removes the lost zone after the workflow has
// proved the surviving cluster still processes work without that intervention.
func TestMultiRegionDrainZone(t *testing.T) {
	env := testEnv(t)

	if env.ActiveRegions < 3 {
		t.Skipf("need at least 3 active regions, have %d", env.ActiveRegions)
	}

	lostSlot := 0

	// Rehearse the zone removal against the real API before committing it. This
	// fails if the path, zone ID or response shape stops matching; dry-run changes
	// nothing on the cluster.
	helpers.RunProcedure(t, env, 10*time.Minute, "failover.sh",
		strconv.Itoa(lostSlot), "--drain-brokers", "--dry-run")

	// Exercise the real membership change after proving the cluster survived the
	// loss without it. failover.sh verifies the reduced topology afterwards, and
	// TestMultiRegionFailback covers the matching POST that restores the zone.
	helpers.RunProcedure(t, env, 20*time.Minute, "failover.sh",
		strconv.Itoa(lostSlot), "--drain-brokers")
}

// TestMultiRegionFailback brings the lost region back.
func TestMultiRegionFailback(t *testing.T) {
	env := testEnv(t)

	if env.ActiveRegions < 3 {
		t.Skipf("need at least 3 active regions, have %d", env.ActiveRegions)
	}

	lostSlot := 0

	defer helpers.RunProcedureAllowFailure(t, env, 5*time.Minute, "submariner/diagnose-submariner.sh")
	helpers.RunProcedure(t, env, 45*time.Minute, "failback.sh", strconv.Itoa(lostSlot))
}

// TestMultiRegionCleanup uninstalls Camunda from every region so that the
// Terraform destroy is not blocked by Kubernetes-managed cloud resources.
func TestMultiRegionCleanup(t *testing.T) {
	env := testEnv(t)
	helpers.RunProcedureAllowFailure(t, env, 20*time.Minute, "cleanup.sh")
}
