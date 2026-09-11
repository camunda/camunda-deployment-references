################################
# Region Configuration        #
################################

variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region for the primary (owner) cluster (must match infra/ and vpc/ configuration)"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region for the secondary (accepter) cluster (must match infra/ and vpc/ configuration)"
}

################################
# Infra State Reference       #
################################

variable "terraform_backend_bucket" {
  type        = string
  description = "S3 bucket name storing Terraform state for all layers"
}

variable "terraform_backend_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region of the S3 bucket storing Terraform state (may differ from the deployment regions)"
}

variable "terraform_backend_key_prefix" {
  type        = string
  description = "S3 key prefix shared by all layers. E.g. 'aws/containers/ecs-dual-region-fargate/my-cluster/' yields 's3://<bucket>/<prefix>infra/terraform.tfstate'"
}

################################
# App Variables               #
################################

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

variable "camunda_image" {
  type = string
  # Dual-region requires the SNAPSHOT build: zone-aware partition distribution
  # (cross-region "region awareness") is only available there and ships in the
  # 8.10 alpha3 image. Keep SNAPSHOT until then; the trailing marker tells the
  # alpha-availability check to skip this line (see internal_global_alpha_availability_check.yml).
  # TODO: [release-duty] at 8.10 alpha3, bump to the published alpha image tag
  # and remove the "alpha-availability-check:ignore" markers in this file.
  default     = "camunda/camunda:8.10-SNAPSHOT" # alpha-availability-check:ignore
  description = "Container image for the Camunda orchestration cluster tasks (Zeebe broker + gateway + webapps)"
}

variable "rdbms_jdbc_url" {
  type        = string
  default     = null
  description = "Full override for the RDBMS secondary-storage JDBC URL. When null (default), the URL is composed from the infra layer's aurora_jdbc_* component outputs. Set it to point this app layer at a database provisioned outside this reference architecture, or at an infra state that predates those outputs. Taken verbatim: neither the infra-provided parameters nor rdbms_extra_jdbc_params are appended to it. Only used when secondary storage is 'rdbms'."
}

variable "rdbms_extra_jdbc_params" {
  type        = map(string)
  default     = {}
  description = "Extra query parameters for the RDBMS secondary-storage JDBC URL, e.g. { connectTimeout = \"5000\" }. Merged over the parameters the infra layer supplies (aurora_jdbc_url_parameters), so retuning one of them — failoverTimeoutMs, say — needs neither a re-apply of the infrastructure state nor a hand-written replacement URL. Ignored when rdbms_jdbc_url is set, since that override is taken verbatim. Only used when secondary storage is 'rdbms'."

  # Mirrors the guards on the Aurora module's own extra_url_parameters, because
  # this map is interpolated into the same query string. Shape first: without
  # it a single entry such as { connectTimeout = "5000&wrapperPlugins=none" }
  # renders a second wrapperPlugins, and which occurrence the driver honours is
  # driver-specific — which would also defeat the reserved-key check below,
  # since that inspects only the keys it was handed.
  validation {
    condition = alltrue([
      for k, v in var.rdbms_extra_jdbc_params :
      can(regex("^[A-Za-z][A-Za-z0-9]*$", k)) && can(regex("^[A-Za-z0-9._:/,-]+$", v))
    ])
    error_message = "rdbms_extra_jdbc_params keys must be bare JDBC parameter names (letters and digits, starting with a letter) and values may contain only letters, digits and . _ : / , - — notably no '&' or '=', so that no entry can append a parameter of its own."
  }

  # Compared lower-cased, mirroring the module: the reserved list is a closed set
  # of exact strings, so a variant differing only in case would otherwise reach
  # the query string, and whether a driver honours it is driver-specific.
  validation {
    condition = length(setintersection(
      [for k in keys(var.rdbms_extra_jdbc_params) : lower(k)],
      ["wrapperplugins", "globalclusterinstancehostpatterns", "sslmode"],
    )) == 0
    error_message = "rdbms_extra_jdbc_params must not contain the parameters composed from the infra layer's engine-derived outputs (wrapperPlugins, globalClusterInstanceHostPatterns, sslmode/sslMode), in any capitalisation. Extend the plugin list through the infra layer's db_extra_wrapper_plugins; the TLS mode and host patterns are not overridable. Use rdbms_jdbc_url to replace the URL outright."
  }
}

variable "connectors_image" {
  type = string
  # Pinned to SNAPSHOT for the same reason as camunda_image above (dual-region
  # region awareness ships in 8.10 alpha3).
  # TODO: [release-duty] at 8.10 alpha3, bump to the published alpha image tag
  # and remove the "alpha-availability-check:ignore" marker.
  default     = "camunda/connectors-bundle:8.10-SNAPSHOT" # alpha-availability-check:ignore
  description = "Container image for the Camunda connectors-bundle tasks. Separate from camunda_image because connectors ship as a distinct artifact from the orchestration cluster."
}
