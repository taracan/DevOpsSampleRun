variable "project" {
  description = "Project name, used as the bucket name prefix."
  type        = string
  default     = "smallproject"
}

variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}
