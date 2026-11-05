mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
  mock_resource "aws_rds_global_cluster" {
    defaults = {
      id       = "demo-global-db"
      endpoint = "demo-global-db.global-abc.global.rds.amazonaws.com"
    }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      cluster_resource_id = "cluster-SECONDARY"
      endpoint            = "demo-camunda-db-b.cluster-xyz.eu-north-1.rds.amazonaws.com"
      cluster_identifier  = "demo-camunda-db-b"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-north-1:000000000000:key/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
}

variables {
  prefix                     = "demo"
  region_a                   = "eu-west-1"
  region_b                   = "eu-north-1"
  source_cluster_arn         = "arn:aws:rds:eu-west-1:000000000000:cluster:demo-camunda-db-cluster"
  source_cluster_identifier  = "demo-camunda-db-cluster"
  source_cluster_endpoint    = "demo-camunda-db-cluster.cluster-abc.eu-west-1.rds.amazonaws.com"
  source_cluster_resource_id = "cluster-PRIMARY"
  vpc_id_a                   = "vpc-aaa"
  vpc_cidr_a                 = "10.190.0.0/16"
  vpc_id_b                   = "vpc-bbb"
  vpc_cidr_b                 = "10.191.0.0/16"
  private_subnet_ids_b       = ["subnet-b1", "subnet-b2", "subnet-b3"]
}

run "global_cluster_is_created_from_the_existing_cluster" {
  command = plan

  assert {
    condition     = aws_rds_global_cluster.this.source_db_cluster_identifier == var.source_cluster_arn
    error_message = "the global cluster must be created from the existing cluster, not replace it"
  }
}

run "connect_policy_covers_both_clusters" {
  command = apply

  assert {
    condition     = length(jsondecode(aws_iam_policy.rds_db_connect["camunda"].policy).Statement[0].Resource) == 2
    error_message = "the connect policy must name both clusters: after a failover the writer is the other one"
  }
}

run "jdbc_url_uses_the_global_endpoint_and_wrapper_plugins" {
  command = apply

  assert {
    condition = alltrue([
      strcontains(output.secondary_storage.jdbc_url, "global.rds.amazonaws.com"),
      strcontains(output.secondary_storage.jdbc_url, "wrapperPlugins=initialConnection,iam,failover"),
      strcontains(output.secondary_storage.jdbc_url, "globalClusterInstanceHostPatterns="),
    ])
    error_message = "the URL must target the global endpoint and carry the wrapper settings an Aurora Global endpoint needs"
  }
}

run "burstable_secondary_rejected" {
  command = plan

  variables {
    secondary_instance_class = "db.t3.medium"
  }

  expect_failures = [var.secondary_instance_class]
}
