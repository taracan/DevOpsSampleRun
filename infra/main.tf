# main.tf: Terraform settings shared by every other file in infra/.
#
# What Terraform is: you describe the AWS resources you want in .tf
# files, and `terraform apply` creates or updates them to match. All .tf
# files in this folder form ONE project; this file holds the setup the
# others rely on:
#   - terraform {}  the required Terraform/AWS provider versions, and
#                   where the "state" is stored. State is Terraform's
#                   record of what it created.
#   - provider {}   which AWS region to use, plus tags added to everything.
#   - locals {}     shared values (name prefix, network ranges) the
#                   other files reuse.
#
# State lives in the S3 bucket smallproject-tfstate-631571737116. It was
# created once by hand-run bootstrap; its own state is in
# infra/bootstrap/terraform.tfstate, which is not committed.
#
# Usage (from the repo root, after `aws login`):
#   eval "$(aws configure export-credentials --format env)"
#   terraform -chdir=infra init
#   terraform -chdir=infra plan
#   terraform -chdir=infra apply

terraform {
  # 1.10+ supports locking the state with a lock file in S3 (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "smallproject-tfstate-631571737116"
    key          = "smallproject/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = local.region

  # Added to every resource, so you can find them all in the console
  # (Resource Groups & Tag Editor -> tag Project = smallproject).
  default_tags {
    tags = {
      Project   = "smallproject"
      ManagedBy = "terraform"
    }
  }
}

locals {
  name   = "smallproject" # prefix for resource names
  region = "us-east-1"

  # Two availability zones (separate data centers): the load balancer
  # and RDS both require subnets in at least two.
  azs = ["us-east-1a", "us-east-1b"]

  vpc_cidr             = "10.0.0.0/16"                    # the whole private network
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]   # load balancer, NAT
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"] # ECS, RDS, EC2

  app_port = 8000 # port the backend container listens on
  db_port  = 5432 # PostgreSQL

  account = data.aws_caller_identity.current.account_id

  # Names of resources created in later steps. They are fixed here so
  # the IAM policies (iam.tf) can point at exact resources before those
  # exist.
  ecr_repo       = "${local.name}-backend"                  # step 7: Docker image repository
  cluster        = local.name                               # step 7: ECS cluster
  service        = "${local.name}-backend"                  # step 7: ECS service running the API
  task_family    = "${local.name}-backend"                  # step 7: ECS task definition
  web_bucket     = "${local.name}-web-${local.account}"     # step 6: React build
  reports_bucket = "${local.name}-reports-${local.account}" # step 6: nightly CSV reports
  state_machine  = "${local.name}-report"                   # step 9: Step Functions job
}

# Looks up the AWS account ID (used in bucket names and ARNs).
data "aws_caller_identity" "current" {}
