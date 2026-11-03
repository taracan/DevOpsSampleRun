# outputs.tf: values Terraform prints after `apply`.

output "site_url" {
  description = "The public website address."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# terraform.yml copies these into the GitHub environment (alpha or beta) as
# variables, next to the backend's (infra/backend/outputs.tf).
# deploy-frontend.yml reads them; deploy-backend.yml's smoke test uses SITE_URL.
output "github_vars" {
  value = {
    AWS_REGION                 = local.region
    FRONTEND_ROLE_ARN          = aws_iam_role.github.arn
    WEB_BUCKET                 = aws_s3_bucket.web.bucket
    CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.main.id
    SITE_URL                   = "https://${aws_cloudfront_distribution.main.domain_name}"
  }
}
