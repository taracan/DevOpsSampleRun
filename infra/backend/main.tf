# main.tf: Terraform settings shared by every other file in infra/backend/.
#
# infra/backend/ is the backend's AWS stack: network, ECS, load balancer,
# database, admin host, jobs, alarms, trail. The website (S3 + CloudFront)
# is a separate stack in infra/frontend/, with its own state and workflow.
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
# State lives in the S3 bucket smallproject-tfstate-631571737116, one file
# per environment (envs/<env>/state.tfbackend). The bucket was created
# once by hand-run bootstrap; its own state is in
# infra/bootstrap/terraform.tfstate, which is not committed.
#
# Usage: GitHub Actions runs Terraform (.github/workflows/terraform.yml):
# deploy-backend.yml calls it with stack=backend: a plan on every PR that
# touches infra/backend/ or backend/, apply to dev on merge to main, apply
# to beta from release.yml; plus a Run workflow button for apply/destroy.

terraform {
  # 1.10+ supports locking the state with a lock file in S3 (use_lockfile).
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

  # Added to every resource, so you can find them all in the console
  # (Resource Groups & Tag Editor -> tag Project = smallproject).
  default_tags {
    tags = {
      Project     = "smallproject"
      Environment = var.env
      Component   = "backend" # infra/frontend/ tags its resources "frontend"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name   = var.name # prefix for resource names: smallproject (dev), smallproject-beta
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
  reports_bucket = "${local.name}-reports-${local.account}" # step 6: nightly CSV reports
  state_machine  = "${local.name}-report"                   # step 9: Step Functions job
}

# Looks up the AWS account ID (used in bucket names and ARNs).
data "aws_caller_identity" "current" {}
