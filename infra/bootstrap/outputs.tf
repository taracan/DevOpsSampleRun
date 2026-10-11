output "state_bucket" {
  description = "Put this value in infra/envs/dev.backend.hcl as `bucket`."
  value       = aws_s3_bucket.state.bucket
}
