variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "smallproject"
}

variable "env" {
  description = "Environment name (dev, prod)."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Address range for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (at least 2)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One public subnet per AZ, for the ALB."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One private subnet per AZ, for ECS, EC2 and RDS."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper; dev only)."
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Port the backend container listens on."
  type        = number
  default     = 8000
}
