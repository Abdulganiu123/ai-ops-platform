resource "aws_ssm_parameter" "guardrail" {
  # checkov:skip=CKV2_AWS_34: guardrail id is a non-secret identifier, not a credential
  name        = "/${var.project_name}/guardrail"
  description = "Guardrail id and version for the devgen CLI to apply."
  type        = "String"

  value = jsonencode({
    id      = aws_bedrock_guardrail.devgen.guardrail_id
    version = "DRAFT"
  })
}
