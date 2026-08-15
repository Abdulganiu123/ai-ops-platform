resource "aws_ssm_parameter" "guardrail" {
  name        = "/${var.project_name}/guardrail"
  description = "Guardrail id and version for the devgen CLI to apply."
  type        = "String"

  value = jsonencode({
    id      = aws_bedrock_guardrail.devgen.guardrail_id
    version = "DRAFT"
  })
}
