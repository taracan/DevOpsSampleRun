# trail.tf: a CloudTrail trail, so EventBridge receives "via CloudTrail" events.
#
# Why this exists (Phase B, step 7): the backend restarts as soon as RDS
# changes the database password (jobs.tf, rule "db-password-rotated"). That
# rule listens for Secrets Manager's RotationSucceeded event, which reaches
# EventBridge as an "AWS Service Event via CloudTrail". AWS only delivers
# those when a trail exists:
#   "To record events with one of the CloudTrail detail-type values, you
#    must enable a CloudTrail trail with logging."
#   (EventBridge User Guide, "AWS service events delivered via AWS CloudTrail")
# Without a trail the rule never fired: on 2026-10-22 a password change went
# unnoticed and /api/v1/ready failed for about 10 3/4 hours.
#
# What it is: CloudTrail is AWS's activity log. A "trail" also writes that
# log to an S3 bucket and forwards the events to EventBridge.
#   - This region only, management events only (the default): enough for
#     the rotation event, and the cheapest setup.
#   - Cost: "You can deliver one copy of your ongoing management events to
#     your Amazon Simple Storage Service (S3) bucket for free" (CloudTrail
#     pricing page). The S3 storage for the log files is charged (rate not
#     stated there), so log files are deleted after 30 days.
#   - The bucket policy is AWS's documented one (CloudTrail User Guide,
#     "Amazon S3 bucket policy for CloudTrail"): CloudTrail may check the
#     bucket ACL and write under AWSLogs/<account>/, only for this trail
#     (aws:SourceArn).
#
# Check it's working: aws cloudtrail get-trail-status --name smallproject
#   (IsLogging should be true)

locals {
  trail_name   = local.name # "smallproject"
  trail_bucket = "${local.name}-cloudtrail-${local.account}"
  trail_arn    = "arn:aws:cloudtrail:${local.region}:${local.account}:trail/${local.trail_name}"
}

resource "aws_s3_bucket" "trail" {
  bucket        = local.trail_bucket
  force_destroy = true # dev only: destroy even if not empty
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Log files are only needed briefly here; delete them after 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "delete-after-30-days"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck20150319"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "AWSCloudTrailWrite20150319"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = false
  include_global_service_events = false
  enable_logging                = true

  # CloudTrail checks the bucket policy when the trail is created.
  depends_on = [aws_s3_bucket_policy.trail]
}
