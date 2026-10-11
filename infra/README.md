# Infrastructure (Terraform)

## Layout
- `bootstrap/` – one-time: S3 bucket for Terraform state (versioned, encrypted, locked). Local state.
- `modules/` – `network` (step 3); `iam`, `secrets`, `data`, `ecr`, `ecs`, `cdn`, `ec2`, `jobs`, `monitoring` are filled in by steps 4–9.
- `envs/dev.tfvars` – dev settings. `envs/dev.backend.hcl` – state bucket name.

## First-time setup
Requires Terraform >= 1.10 and AWS credentials for the target account.

```bash
cd infra/bootstrap
terraform init
terraform apply          # note the state_bucket output
```

Put the `state_bucket` value into `envs/dev.backend.hcl`, then:

```bash
cd infra
terraform init -backend-config=envs/dev.backend.hcl
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
terraform plan  -var-file=envs/dev.tfvars   # should report "No changes"
```

## Network (step 3)
- VPC `10.0.0.0/16` across 2 AZs; public subnets (ALB) and private subnets (ECS, EC2, RDS).
- One NAT gateway in dev (`single_nat_gateway = false` for one per AZ), plus a free S3 gateway endpoint.
- Security groups: ALB ← CloudFront prefix list only; ECS ← ALB only; RDS ← ECS and EC2 admin only; EC2 admin has no inbound (SSM).

## Cost
The NAT gateway is ~$32/month plus data. Run `terraform destroy -var-file=envs/dev.tfvars` when idle (the state bucket is kept).
