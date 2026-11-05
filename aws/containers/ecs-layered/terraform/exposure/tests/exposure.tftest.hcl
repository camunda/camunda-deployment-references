mock_provider "aws" {}

variables {
  prefix                          = "test"
  vpc_id                          = "vpc-0abc123"
  public_subnet_ids               = ["subnet-a1", "subnet-b2", "subnet-c3"]
  camunda_ports_security_group_id = "sg-ports"
}

run "plain_http_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.https_webapp) == 0 && length(aws_lb_listener_rule.http_to_https_redirect) == 0
    error_message = "no TLS listener without a certificate"
  }
}

run "tls_needs_public_hostname" {
  command = plan

  variables {
    alb_certificate_arn = "arn:aws:acm:eu-west-1:000000000000:certificate/abc"
  }

  expect_failures = [var.alb_public_hostname]
}

run "tls_with_hostname" {
  command = plan

  variables {
    alb_certificate_arn = "arn:aws:acm:eu-west-1:000000000000:certificate/abc"
    alb_public_hostname = "camunda.example"
  }

  assert {
    condition     = length(aws_lb_listener.https_webapp) == 1 && output.public_base_url == "https://camunda.example"
    error_message = "a certificate must enable the HTTPS listener and an https base URL"
  }
}

run "raft_nlb_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb.raft) == 0 && output.nlb_raft_arn == ""
    error_message = "no internal NLB unless asked for"
  }
}

run "raft_nlb_needs_private_subnets" {
  command = plan

  variables {
    enable_raft_nlb = true
  }

  expect_failures = [aws_lb.raft]
}

run "raft_nlb_created_when_enabled" {
  command = plan

  variables {
    enable_raft_nlb    = true
    private_subnet_ids = ["subnet-p1", "subnet-p2", "subnet-p3"]
  }

  assert {
    condition     = length(aws_lb.raft) == 1
    error_message = "enable_raft_nlb must create the internal NLB"
  }
}
