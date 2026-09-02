################################################################
#                        App Outputs                           #
################################################################

output "region_0_alb_endpoint" {
  value       = local.infra.region_0_alb_endpoint
  description = "The DNS name of the ALB in region 0 (HTTP/REST access)"
}

output "region_1_alb_endpoint" {
  value       = local.infra.region_1_alb_endpoint
  description = "The DNS name of the ALB in region 1 (HTTP/REST access)"
}

output "region_0_nlb_grpc_endpoint" {
  value       = local.infra.region_0_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 0 (gRPC access)"
}

output "region_1_nlb_grpc_endpoint" {
  value       = local.infra.region_1_nlb_grpc_endpoint
  description = "The DNS name of the external NLB in region 1 (gRPC access)"
}

output "region_0_log_group_name" {
  value       = module.orchestration_cluster_region_0.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 0"
}

output "region_1_log_group_name" {
  value       = module.orchestration_cluster_region_1.log_group_name
  description = "CloudWatch log group for the orchestration cluster in region 1"
}

output "admin_user_password" {
  value       = local.infra.admin_user_password
  description = "The admin password for Camunda"
  sensitive   = true
}

# Shown at the end of `terraform apply` so the operator immediately sees how to
# retrieve credentials and reach the deployment. Non-sensitive (commands only;
# the password itself is fetched separately via `terraform output -raw …`).
output "next_steps" {
  description = "Operator handover: how to fetch credentials and access the deployment."
  value       = <<-EOT

    ════════════════════════════════════════════════════════════════════
    Camunda 8 dual-region ECS deployment is ready.
    ════════════════════════════════════════════════════════════════════

    ── 1. Retrieve the admin credentials ──────────────────────────────

      # Username is "admin"; password is generated and stored in Secrets Manager.
      # Run from this directory (terraform/app/):
      ADMIN_PASS=$(terraform output -raw admin_user_password)
      echo "admin / $ADMIN_PASS"

      # Connectors password (used by the connectors-bundle to call the
      # orchestration cluster):
      aws secretsmanager get-secret-value \
        --secret-id ${local.infra.connectors_password_secret_region_0_arn} \
        --region ${data.aws_region.region_0.region} \
        --query SecretString --output text

    ── 2. Health-check (basic auth required on 8.10) ──────────────────

      curl -s -u "admin:$ADMIN_PASS" \
        http://${local.infra.region_0_alb_endpoint}/v2/topology \
        | jq '{brokerCount: (.brokers | length), clusterSize, replicationFactor}'
      # Expect: brokerCount=${local.cluster_size}, clusterSize=${local.cluster_size},
      # replicationFactor=${local.replication_factor}. Raft can take 15-20 min
      # the first time before all partitions have a leader.

    ── 3. Open the Web UI ─────────────────────────────────────────────

      # Method A — direct via the ALB (default; reachable from limit_access_to_cidrs):
      open http://${local.infra.region_0_alb_endpoint}/operate
      # Login: admin / <ADMIN_PASS from step 1>

      # Method B — Session Manager port-forward (no public ingress required):
      #   See "Method B" in aws/containers/ecs-dual-region-fargate/README.md
      #   Requires `session-manager-plugin` and ECS Exec enabled on the task
      #   (this reference architecture sets it to true by default).

    ── 4. CloudWatch logs ─────────────────────────────────────────────

      aws logs tail ${module.orchestration_cluster_region_0.log_group_name} --region ${data.aws_region.region_0.region} --follow
      aws logs tail ${module.orchestration_cluster_region_1.log_group_name} --region ${data.aws_region.region_1.region} --follow

    ── 5. Region 1 endpoints (active-active, same credentials) ────────

      Region 1 ALB:  http://${local.infra.region_1_alb_endpoint}
      Region 1 gRPC: ${local.infra.region_1_nlb_grpc_endpoint}:26500

    ════════════════════════════════════════════════════════════════════
  EOT
}
