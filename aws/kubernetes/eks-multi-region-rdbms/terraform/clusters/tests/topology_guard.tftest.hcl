# Guard tests for the region topology.
#
# The invariants live in a precondition rather than a `check` block precisely so
# that they FAIL a plan instead of warning through it, and these tests assert
# that difference: a topology without a quorum has to stop the apply.
#
# `expect_failures` names the guard resource specifically, so a regression that
# breaks some unrelated resource cannot make the test pass by accident.
#
# mock_provider keeps this offline; no AWS call is made.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "region_1"
}
mock_provider "aws" {
  alias = "region_2"
}
mock_provider "aws" {
  alias = "region_3"
}
mock_provider "random" {}
mock_provider "time" {}

# The EKS module carries its own preconditions, notably an Elastic IP quota
# check that reads service quotas at plan time. Against mocked providers those
# reads return zero and the module fails before the topology guard is reached,
# which would make this file assert nothing. Stubbing the modules keeps the plan
# focused on the guard under test.
override_module {
  target = module.eks_cluster_region_0
  outputs = {
    vpc_id                            = "vpc-00000000000000000"
    vpc_azs                           = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    vpc_main_route_table_id           = "rtb-00000000000000000"
    private_route_table_ids           = ["rtb-00000000000000001"]
    private_subnet_ids                = ["subnet-00000000000000000"]
    cluster_primary_security_group_id = "sg-00000000000000000"
    oidc_provider_arn                 = "arn:aws:iam::000000000000:oidc-provider/example"
  }
}

override_module {
  target = module.eks_cluster_region_1
  outputs = {
    vpc_id                            = "vpc-00000000000000001"
    vpc_azs                           = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
    vpc_main_route_table_id           = "rtb-00000000000000010"
    private_route_table_ids           = ["rtb-00000000000000011"]
    private_subnet_ids                = ["subnet-00000000000000001"]
    cluster_primary_security_group_id = "sg-00000000000000001"
    oidc_provider_arn                 = "arn:aws:iam::000000000000:oidc-provider/example"
  }
}

override_module {
  target = module.eks_cluster_region_2
  outputs = {
    vpc_id                            = "vpc-00000000000000002"
    vpc_azs                           = ["eu-central-2a", "eu-central-2b", "eu-central-2c"]
    vpc_main_route_table_id           = "rtb-00000000000000020"
    private_route_table_ids           = ["rtb-00000000000000021"]
    private_subnet_ids                = ["subnet-00000000000000002"]
    cluster_primary_security_group_id = "sg-00000000000000002"
    oidc_provider_arn                 = "arn:aws:iam::000000000000:oidc-provider/example"
  }
}

override_module {
  target = module.eks_cluster_region_3
  outputs = {
    vpc_id                            = "vpc-00000000000000003"
    vpc_azs                           = ["eu-south-1a", "eu-south-1b", "eu-south-1c"]
    vpc_main_route_table_id           = "rtb-00000000000000030"
    private_route_table_ids           = ["rtb-00000000000000031"]
    private_subnet_ids                = ["subnet-00000000000000003"]
    cluster_primary_security_group_id = "sg-00000000000000003"
    oidc_provider_arn                 = "arn:aws:iam::000000000000:oidc-provider/example"
  }
}

variables {
  cluster_name = "test-topology-guard"
}

run "a_topology_without_a_quorum_fails_the_plan" {
  command = plan

  variables {
    # Four declared slots with two active. It clears the per-variable rule that
    # only rejects fewer than two regions, and still leaves every partition with
    # two replicas of four, which is not a majority. This is the case a `check`
    # block used to wave through with a warning.
    regions = [
      {
        region             = "eu-west-2"
        short_name         = "london"
        vpc_cidr_block     = "10.192.0.0/16"
        service_cidr_block = "10.190.0.0/16"
      },
      {
        region             = "eu-west-3"
        short_name         = "paris"
        vpc_cidr_block     = "10.202.0.0/16"
        service_cidr_block = "10.200.0.0/16"
      },
      {
        region             = "eu-central-2"
        short_name         = "zurich"
        vpc_cidr_block     = "10.212.0.0/16"
        service_cidr_block = "10.210.0.0/16"
      },
      {
        region             = "eu-south-1"
        short_name         = "milan"
        vpc_cidr_block     = "10.222.0.0/16"
        service_cidr_block = "10.220.0.0/16"
      },
    ]
    active_region_count = 2
  }

  expect_failures = [terraform_data.topology_guard]
}

run "the_default_topology_is_accepted" {
  command = plan
}
