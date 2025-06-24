# Overwrite the default values for the locals used in ci tests.
locals {
  generate_ssh_key_pair = "true"
  opensearch_enable     = "false" # TODO: Temporary for the tests, remove when ready
  enable_alb            = "false" # TODO: Temporary for the tests, remove when ready
  enable_nlb            = "false" # TODO: Temporary for the tests, remove when ready
}
