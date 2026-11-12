variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "vpc_id" {
  type        = string
  description = "Network stage output: ID of the VPC"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Network stage output: public subnet IDs for the internet-facing load balancers"
}

variable "camunda_ports_security_group_id" {
  type        = string
  description = "Compute stage output: security group that opens the Camunda ports inside the VPC"
}

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the load balancers. The default is open to the internet: restrict it."
}

variable "alb_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN. When set, the ALB serves HTTPS on 443 and HTTP on 80 redirects to it. Empty keeps plain HTTP on 80, for a demo."
}

variable "alb_ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  description = "SSL negotiation policy of the HTTPS listener (used only when alb_certificate_arn is set)"
}

variable "alb_public_hostname" {
  type        = string
  default     = ""
  description = "DNS name clients use to reach the ALB (for example an alias record you create). Required with alb_certificate_arn: ACM cannot issue a certificate for the ALB's own *.elb.amazonaws.com name. Empty falls back to the ALB's DNS name."

  validation {
    condition     = var.alb_certificate_arn == "" || trimspace(var.alb_public_hostname) != ""
    error_message = "alb_public_hostname must be set when alb_certificate_arn is set."
  }
}

variable "enable_raft_nlb" {
  type        = bool
  default     = false
  description = "Create an internal network load balancer for the cluster's internal traffic (26502). A second region's brokers join the cluster through it. Set it to true from the start if you expect to add a region: adding it later makes the Camunda stage register a target group on an existing ECS service, which Terraform may replace."
}

variable "private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Network stage output: private subnet IDs. Required when enable_raft_nlb = true."
}
