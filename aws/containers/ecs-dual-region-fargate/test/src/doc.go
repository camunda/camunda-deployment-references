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
