# variables.tf: the settings that differ between environments.
#
# Dev, qa and beta live in the same AWS account, as three copies of this stack (and of infra/backend/)
# with different names. Each copy's values are in envs/<env>/terraform.tfvars,
# and its state file is chosen by envs/<env>/state.tfbackend.
# terraform.yml passes both, so Terraform is never run from a laptop.

variable "env" {
  description = "Which environment this copy is: dev, qa or beta."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "beta"], var.env)
    error_message = "env must be dev, qa or beta."
  }
}

variable "name" {
  description = "Prefix for every resource name. Dev keeps the original \"smallproject\" so nothing is renamed or rebuilt."
  type        = string
}
