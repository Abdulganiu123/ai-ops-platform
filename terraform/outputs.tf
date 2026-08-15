output "guardrail_id" {
  description = "Pass this to the Bedrock Converse API as guardrailIdentifier."
  value       = aws_bedrock_guardrail.devgen.guardrail_id
}

output "guardrail_version" {
  description = "Guardrail version to use. DRAFT tracks the current config."
  value       = "DRAFT"
}

output "invoke_policy_arn" {
  description = "Attach this policy to the role or user running devgen."
  value       = aws_iam_policy.devgen_invoke.arn
}

output "log_group_name" {
  description = "CloudWatch log group holding Bedrock invocation metadata."
  value       = aws_cloudwatch_log_group.bedrock.name
}

output "ci_role_arn" {
  description = "Set this as the AWS_CI_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.ci.arn
}