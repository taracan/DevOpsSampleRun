# cdn.tf: CloudFront, the public front door of the site.
#
#   Browser --HTTPS--> CloudFront (https://<id>.cloudfront.net)
#                        |-- /api/*  --> ALB --> ECS backend   (never cached)
#                        '-- else    --> S3 web bucket (React build, cached)
#
# What CloudFront is: a global CDN. Visitors connect to the nearest AWS
# edge location over HTTPS, using CloudFront's default certificate. It
# serves the React files from cache and forwards API calls to the
# backend. Because the page and the API share one address, the browser
# needs no CORS setup.
#
# Security:
#   - S3 stays private. Origin Access Control (OAC) lets CloudFront sign
#     its requests, and the bucket policy only allows reads signed by
#     THIS distribution.
#   - The ALB only accepts CloudFront's IP ranges (network.tf).
#
# React routing: pages like /success exist only in the browser, not as
# files in S3. When S3 answers "not found" (403/404), CloudFront returns
# index.html instead, so refreshing /success still loads the app.
#
# Cost: within the free tier for this traffic (1 TB/month out).

# AWS-managed cache settings, looked up by name.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized" # static files: cache
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled" # API: never cache
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewerExceptHostHeader" # API: pass through headers, query, cookies
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${local.name}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest: North America and Europe edges

  # Origin 1: the React build in S3.
  origin {
    origin_id                = "web"
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  # Origin 2: the backend, through the load balancer (HTTP inside AWS).
  origin {
    origin_id   = "api"
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default: everything else is a static file from S3.
  default_cache_behavior {
    target_origin_id       = "web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # /api/*: forwarded to the backend, all methods, no caching.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  # React routing fallback (see the header).
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # HTTPS on *.cloudfront.net
  }
}

# Only this distribution may read the web bucket.
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.main.arn }
      }
    }]
  })
}
