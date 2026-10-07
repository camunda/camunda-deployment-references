# Tests for the optional load-test overlay.
#
# The overlay is the part of camunda/camunda-load-tests-ecs that survived the
# fold: a long-lived Prometheus plus a load generator, attached to the cluster
# this reference already builds. It is opt-in because a reference architecture
# should not ship a benchmark to everyone who copies it, so the case that
# matters most is the one where the flag is off and the plan is unchanged.

mock_provider "aws" {}
mock_provider "random" {}
mock_provider "null" {}

# The mocked provider returns an empty AZ list, which slice() in vpc.tf rejects
# before any of the assertions below are reached.
override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

override_data {
  target = data.aws_servicequotas_service_quota.elastic_ip_quota
  values = {
    value = 100
  }
}

override_data {
  target = data.aws_eips.current_usage
  values = {
    public_ips = []
  }
}

override_data {
  target = data.aws_vpcs.current_vpcs
  values = {
    ids = []
  }
}

run "load_tests_absent_by_default" {
  command = plan

  assert {
    condition     = output.prometheus_endpoint == null
    error_message = "No Prometheus should be planned unless enable_load_tests is set"
  }

  assert {
    condition     = output.load_generator_log_group == null
    error_message = "No load generator should be planned unless enable_load_tests is set"
  }

  assert {
    condition     = output.load_generator_target == null
    error_message = "No load generator target should be reported unless enable_load_tests is set"
  }
}

run "load_tests_wired_when_enabled" {
  command = plan

  variables {
    enable_load_tests = true
  }

  assert {
    condition     = output.prometheus_endpoint != null
    error_message = "Prometheus should be planned when enable_load_tests is true"
  }

  assert {
    condition     = output.load_generator_log_group != null
    error_message = "The load generator should be planned when enable_load_tests is true"
  }
}

run "generator_points_at_this_cluster" {
  command = plan

  variables {
    enable_load_tests = true
    prefix            = "wired"
  }

  # The orchestration-cluster module registers
  # "orchestration-cluster.<prefix>-oc1.service.local" in Cloud Map. Getting
  # this wrong produces a generator that starts, connects to nothing and
  # reports zero throughput without ever failing.
  assert {
    condition     = output.load_generator_target == "orchestration-cluster.wired-oc1.service.local"
    error_message = "The generator should target the orchestration cluster's Cloud Map record"
  }
}

run "overlay_refuses_to_deploy_against_an_oidc_cluster" {
  command = plan

  # The generator wires basic auth only. Against authentication_mode = "oidc"
  # it would start, collect 401s and report zero throughput without failing,
  # so the plan has to stop instead.
  variables {
    enable_load_tests   = true
    authentication_mode = "oidc"
  }

  expect_failures = [aws_security_group.prometheus]
}

run "oidc_cluster_is_fine_without_the_overlay" {
  command = plan

  variables {
    enable_load_tests   = false
    authentication_mode = "oidc"
  }

  assert {
    condition     = output.load_generator_target == null
    error_message = "An OIDC cluster should still plan cleanly when the overlay is off"
  }
}

run "benchmark_cluster_profile_is_off_by_default" {
  command = plan

  # Flow control and provisioned EFS change how the engine and its storage
  # behave for every workload, so the untouched plan must not carry them.
  assert {
    condition     = length(local.benchmark_cluster_environment) == 0
    error_message = "No flow-control settings should be applied while the benchmark profile is off"
  }

  assert {
    condition     = !strcontains(jsonencode(local.benchmark_cluster_environment), "FLOWCONTROL")
    error_message = "Flow control must not leak into the default plan"
  }
}

run "benchmark_cluster_profile_applies_the_absorbed_settings" {
  command = plan

  variables {
    enable_benchmark_cluster_profile = true
  }

  assert {
    condition     = length(local.benchmark_cluster_environment) == 3
    error_message = "The profile should apply the three flow-control settings the absorbed benchmark ran with"
  }

  assert {
    condition     = strcontains(jsonencode(local.benchmark_cluster_environment), "\"CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_LIMIT\",\"value\":\"10000\"")
    error_message = "The write limit should match the absorbed benchmark"
  }
}
