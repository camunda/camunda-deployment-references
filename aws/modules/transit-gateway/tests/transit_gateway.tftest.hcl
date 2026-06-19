# Tests for the transit-gateway module.
#
# The module declares two providers (aws.owner and aws.accepter). The mock
# providers in this test alias accordingly so the test runs without AWS.

mock_provider "aws" {
  alias = "owner"
}
mock_provider "aws" {
  alias = "accepter"
}

variables {
  prefix = "test-tgw"
}

run "default_plan_succeeds" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.owner.description == "Transit Gateway for test-tgw dual-region ECS"
    error_message = "Owner TGW description should reflect var.prefix"
  }

  assert {
    condition     = aws_ec2_transit_gateway.accepter.description == "Transit Gateway for test-tgw dual-region ECS (accepter)"
    error_message = "Accepter TGW description should reflect var.prefix"
  }
}

run "peering_attachment_planned" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_peering_attachment.owner_to_accepter.tags["Name"] == "test-tgw-tgw-peering"
    error_message = "Peering attachment should be tagged with the prefix"
  }
}
