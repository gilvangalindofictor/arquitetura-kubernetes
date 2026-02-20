# =============================================================================
# TFLint Configuration
# DT-003: Static analysis rules for Terraform IaC
# Place this file at the root of modules/ or reference with --config flag
# =============================================================================

config {
  # Use module inspection for deeper analysis
  module = false

  # Force all rules to be errors (not warnings)
  force = false
}

# =============================================================================
# AWS Plugin - AWS-specific best practices
# =============================================================================
plugin "aws" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# =============================================================================
# Terraform Plugin - General Terraform best practices
# =============================================================================
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# =============================================================================
# Custom Rules
# =============================================================================

# Ensure terraform blocks specify required_version
rule "terraform_required_version" {
  enabled = true
}

# Ensure providers specify version constraints
rule "terraform_required_providers" {
  enabled = true
}

# Variables should have descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Outputs should have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Enforce naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# No deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Typed variables
rule "terraform_typed_variables" {
  enabled = true
}
