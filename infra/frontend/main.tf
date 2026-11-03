# main.tf: Terraform settings for infra/frontend/, the website's AWS stack.
#
# The website is the React build in a private S3 bucket, served by
# CloudFront (cdn.tf). CloudFront also forwards /api/* to the backend's
# load balancer, which infra/backend/ creates; this stack finds it by name
# (data "aws_lb" in cdn.tf), so the two stacks never read each other's state.
#
# State: same bucket as the backend, its own file per environment
# (envs/<env>/state.tfbackend).
#
# Usage: GitHub Actions runs Terraform (.github/workflows/terraform.yml);
# deploy-frontend.yml calls it with stack=frontend: a plan on every PR that
# touches infra/frontend/ or frontend/, apply to alpha on merge to alpha, apply
# to beta from release.yml. The backend must be applied first.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Filled in by `terraform init -backend-config=envs/<env>/state.tfbackend`.
  backend "s3" {}
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = "smallproject"
      Environment = var.env
      Component   = "frontend"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name       = var.name # smallproject (alpha), smallproject-beta
  region     = "us-east-1"
  account    = data.aws_caller_identity.current.account_id
  web_bucket = "${local.name}-web-${local.account}" # the React build
}

data "aws_caller_identity" "current" {}
