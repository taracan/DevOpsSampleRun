locals {
  name = "${var.project}-${var.env}"
}

module "network" {
  source = "./modules/network"

  name                 = local.name
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  app_port             = var.app_port
}

# Wired in by later steps:
#   module "iam"        - step 4
#   module "secrets"    - step 4
#   module "data"       - step 5 (RDS, S3 buckets)
#   module "ecr"        - step 6
#   module "ecs"        - step 6 (cluster, service, ALB)
#   module "cdn"        - step 7 (CloudFront)
#   module "ec2"        - step 8 (admin host)
#   module "jobs"       - step 8 (EventBridge + Step Functions)
#   module "monitoring" - step 9 (CloudWatch)
