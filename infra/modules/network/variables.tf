variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "region" {
  description = "AWS region (used for the S3 endpoint service name)."
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "ALB and RDS need at least 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "app_port" {
  description = "Port the backend container listens on."
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}
