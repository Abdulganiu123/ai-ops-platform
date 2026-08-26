output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "ci_role_arn" {
  description = "Set this as the AWS_CI_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.ci.arn
}