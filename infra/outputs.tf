# outputs.tf: values Terraform prints after `apply`.
#
# Outputs are the useful IDs of what was created. See them any time
# with:
#   terraform -chdir=infra output
# Later steps add more here (e.g. the CloudFront URL), and step 10 copies
# some of them into GitHub as repository variables for the deploy
# workflow.

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_ids" {
  value = {
    alb = aws_security_group.alb.id
    ecs = aws_security_group.ecs.id
    ec2 = aws_security_group.ec2.id
    rds = aws_security_group.rds.id
  }
}

output "github_actions_role_arn" {
  description = "Step 10: set as the AWS_ROLE_ARN variable in GitHub."
  value       = aws_iam_role.github.arn
}

output "iam_role_arns" {
  value = {
    ecs_execution = aws_iam_role.ecs_execution.arn
    ecs_task      = aws_iam_role.ecs_task.arn
    ec2           = aws_iam_role.ec2.arn
    sfn           = aws_iam_role.sfn.arn
    scheduler     = aws_iam_role.scheduler.arn
  }
}

output "db_endpoint" {
  description = "RDS hostname; ECS gets it as DB_HOST (step 7)."
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the DB username and password."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "buckets" {
  value = {
    web     = aws_s3_bucket.web.bucket
    reports = aws_s3_bucket.reports.bucket
  }
}

output "ecr_repository_url" {
  description = "Push the backend image here (tag: latest)."
  value       = aws_ecr_repository.backend.repository_url
}

output "alb_dns_name" {
  description = "Load balancer address; CloudFront sends /api/* here (step 8)."
  value       = aws_lb.main.dns_name
}

output "ecs" {
  value = {
    cluster = aws_ecs_cluster.main.name
    service = aws_ecs_service.backend.name
  }
}
