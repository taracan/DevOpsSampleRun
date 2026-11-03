# variables.tf: the settings that differ between environments.
#
# Alpha and beta live in the same AWS account, as two copies of this stack (and of infra/backend/)
# with different names. Each copy's values are in envs/<env>/terraform.tfvars,
# and its state file is chosen by envs/<env>/state.tfbackend.
# terraform.yml passes both, so Terraform is never run from a laptop.

variable "env" {
  description = "Which environment this copy is: alpha or beta."
  type        = string

  validation {
    condition     = contains(["alpha", "beta"], var.env)
    error_message = "env must be alpha or beta."
  }
}

variable "name" {
  description = "Prefix for every resource name. Alpha (the former dev) keeps the original \"smallproject\" so nothing is renamed or rebuilt."
  type        = string
}
