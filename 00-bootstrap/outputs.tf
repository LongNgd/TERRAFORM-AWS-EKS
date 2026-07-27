output "state_bucket_name" {
  description = "S3 bucket used by the infrastructure and platform stacks."
  value       = aws_s3_bucket.terraform_state.id
}
