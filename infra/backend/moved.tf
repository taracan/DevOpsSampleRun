# moved.tf: hands the website's resources over to infra/frontend/.
#
# The website (S3 bucket + CloudFront) used to be part of this stack. It
# now lives in its own stack, infra/frontend/. These `removed` blocks take
# it out of this stack's state WITHOUT deleting anything in AWS
# (destroy = false); infra/frontend/moved.tf imports the same resources.
#
# Delete this file (and infra/frontend/moved.tf) once dev has applied:
# after that the blocks do nothing.

removed {
  from = aws_cloudfront_distribution.main
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_cloudfront_origin_access_control.web
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket.web
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_policy.web
  lifecycle {
    destroy = false
  }
}
