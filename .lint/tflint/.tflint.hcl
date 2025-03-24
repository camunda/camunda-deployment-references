# Standard ruleset documentation: https://github.com/terraform-linters/tflint-ruleset-terraform/tree/main/docs/rules

rule "terraform_naming_convention" {
    enabled = true
    custom = "^[a-z][a-z0-9_]{0,62}[a-z0-9]$"
    module {
        custom = "^[a-z][a-z0-9_]{0,70}[a-z0-9]$"
    }
}

rule "terraform_typed_variables" {
    enabled = false
}

rule "terraform_unused_declarations" {
    enabled = false
}

rule "terraform_required_version" {
    enabled = false
}

rule "terraform_required_providers" {
    enabled = false
}
