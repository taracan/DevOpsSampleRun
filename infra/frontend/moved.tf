# moved.tf: takes over dev's existing website resources from infra/backend/.
#
# Dev's bucket and CloudFront distribution were created when they were part
# of infra/backend/. These `import` blocks adopt them into this stack's
# state as they are, so nothing is rebuilt and the site URL stays the same
# (infra/backend/moved.tf drops them from the backend's state without
# deleting them). Beta is built fresh by this stack, so they apply to dev only.
#
# The origin access control is not imported: this stack makes a new one
# (smallproject-web-oac) and the distribution switches to it in place.
# Delete the old smallproject-web in the CloudFront console afterwards.
#
# Delete this file (and infra/backend/moved.tf) once dev has applied.

locals {
  dev_imports = var.env == "dev" ? toset(["dev"]) : toset([])
}

import {
  for_each = local.dev_imports
  to       = aws_s3_bucket.web
  id       = local.web_bucket
}

import {
  for_each = local.dev_imports
  to       = aws_s3_bucket_policy.web
  id       = local.web_bucket
}

import {
  for_each = local.dev_imports
  to       = aws_cloudfront_distribution.main
  id       = "EWAOVPOVCP7SH" # dev's distribution (https://d3u96oxec6f0pb.cloudfront.net)
}
