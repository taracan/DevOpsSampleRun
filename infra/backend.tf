# Remote state in the bucket created by infra/bootstrap.
# The bucket name is account-specific, so it is passed at init time:
#   terraform init -backend-config=envs/dev.backend.hcl
terraform {
  backend "s3" {
    key          = "smallproject/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
