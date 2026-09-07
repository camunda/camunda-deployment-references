################################################################
#                     Plan-time assertions                     #
################################################################

# The RDBMS JDBC URL is composed from the infra layer's aurora_jdbc_* outputs.
# If the infra state predates those outputs (or secondary storage was switched
# without re-applying infra), the composed value is null and would otherwise be
# assigned to an ECS environment variable, failing later with an opaque type
# error. Assert during plan instead, and name the fix.
resource "terraform_data" "rdbms_jdbc_url_present" {
  count = local.infra.secondary_storage_type == "rdbms" ? 1 : 0

  input = local.rdbms_jdbc_url

  lifecycle {
    precondition {
      condition     = local.rdbms_jdbc_url != null && local.rdbms_jdbc_url != ""
      error_message = <<-EOT
        Could not determine the RDBMS JDBC URL.

        secondary_storage_type is "rdbms", but the infra remote state does not
        expose the aurora_jdbc_* component outputs used to build the URL
        (aurora_jdbc_subprotocol, aurora_global_writer_endpoint, aurora_db_port,
        aurora_jdbc_wrapper_plugins, aurora_jdbc_instance_host_patterns).

        Apply terraform/infra/ first so it publishes them, or set
        var.rdbms_jdbc_url to supply a complete URL yourself.
      EOT
    }
  }
}
