// Package src holds the end-to-end Terratest suite for the ECS dual-region
// Fargate reference architecture.
//
// # No test in this package calls t.Parallel()
//
// Two reasons, and the second is the binding one:
//
//  1. Every test drives `terraform init -reconfigure` against the SAME three
//     module directories on disk — terraform/{vpc,infra,app} — so two at once
//     race on the backend configuration and the shared plugin cache. This is
//     solvable (a per-test TF_DATA_DIR, or copying the repo root with
//     test_structure.CopyTerraformFolderToTemp) if it were the only obstacle.
//
//  2. Each test provisions a complete dual-region stack — two VPCs, an Aurora
//     Global cluster, two ALBs, NAT gateways — in shared CI regions. Running
//     them concurrently multiplies peak spend and pushes against account
//     quotas (Elastic IPs and NAT gateways per region bite first). Serial
//     execution is the cost decision, not a technical limit.
//
// Expect an hour or more of wall clock for a full sweep. CI splits the suite
// across dispatch-only workflows rather than parallelising it here.
package src

// Cluster shape, mirroring terraform/app/locals.tf. Every suite in this
// package asserts against these rather than bare literals, so a topology
// change lands in one place.
//
// The replication factor is the sum over zones: each of the two zones gets
// numberOfReplicas = replication_factor / 2 = 2, so removing a zone removes
// its 2 and the survivor's 2 become the whole factor. That makes the factor —
// not the broker count — the observable that distinguishes a zone leaving the
// persisted distribution from a zone merely becoming unreachable. Brokers
// disappear whenever a region is scaled down either way.
const (
	brokersBothZones = 8
	brokersOneZone   = 4
	partitionCount   = 8
	rfBothZones      = 4
	rfOneZone        = 2
)
