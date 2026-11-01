# iam.tf: the role GitHub Actions uses to deploy the website.
#
# deploy-frontend.yml signs in with it through GitHub's OIDC token (no AWS
# keys stored in GitHub). It is trusted only for jobs in this environment's
# GitHub environment (dev or beta), and may only upload to this
# environment's web bucket and clear this environment's CloudFront cache.
# The backend has its own role (infra/backend/iam.tf).

locals {
  github_oidc_arn = "arn:aws:iam::${local.account}:oidc-provider/token.actions.githubusercontent.com"

  # Immutable subject (owner@<owner id>/repo@<repo id>), as in infra/backend/iam.tf.
  github_sub = "repo:taracan@47918634/DevOpsSampleRun@1410627250"
}

resource "aws_iam_role" "github" {
  name = "${local.name}-github-frontend"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.github_oidc_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.github_sub}:environment:${var.env}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github" {
  name = "deploy"
  role = aws_iam_role.github.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WebsiteList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.web.arn
      },
      {
        Sid      = "WebsiteUpload" # aws s3 sync --delete
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.web.arn}/*"
      },
      {
        Sid      = "CacheClear" # only this site's distribution
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"] # Get: wait until done
        Resource = aws_cloudfront_distribution.main.arn
      },
    ]
  })
}
