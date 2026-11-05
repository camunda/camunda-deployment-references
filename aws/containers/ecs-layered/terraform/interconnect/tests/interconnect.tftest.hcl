mock_provider "aws" {
  mock_resource "aws_route53_resolver_endpoint" {
    defaults = {
      ip_address = [{ ip = "10.0.0.10", subnet_id = "subnet-1", ip_id = "rni-1" }]
    }
  }
}

variables {
  prefix                     = "demo"
  region_a                   = "eu-west-1"
  region_b                   = "eu-north-1"
  vpc_id_a                   = "vpc-aaa"
  vpc_cidr_a                 = "10.190.0.0/16"
  private_subnet_ids_a       = ["subnet-a1", "subnet-a2", "subnet-a3"]
  private_route_table_ids_a  = ["rtb-a1", "rtb-a2"]
  vpc_id_b                   = "vpc-bbb"
  vpc_cidr_b                 = "10.191.0.0/16"
  private_subnet_ids_b       = ["subnet-b1", "subnet-b2", "subnet-b3"]
  private_route_table_ids_b  = ["rtb-b1"]
  service_discovery_domain_a = "demo-oc.service.local"
  service_discovery_domain_b = "demo-b-oc.service.local"
}

run "routes_on_both_sides" {
  command = plan

  assert {
    condition     = length(aws_route.a_to_b) == 2 && length(aws_route.b_to_a) == 1
    error_message = "every private route table needs a route to the other VPC"
  }
}

run "overlapping_cidrs_rejected" {
  command = plan

  variables {
    vpc_cidr_b = "10.190.0.0/16"
  }

  expect_failures = [terraform_data.validate]
}

run "same_region_rejected" {
  command = plan

  variables {
    region_b = "eu-west-1"
  }

  expect_failures = [terraform_data.validate]
}

run "dns_resolver_can_be_turned_off" {
  command = plan

  variables {
    enable_dns_resolver        = false
    service_discovery_domain_a = ""
    service_discovery_domain_b = ""
  }

  assert {
    condition     = length(aws_route53_resolver_rule.a_to_b) == 0
    error_message = "no resolver resources without enable_dns_resolver"
  }
}
