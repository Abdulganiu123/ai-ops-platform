data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Single source of truth: the app's own tier config.
  devgen_config = yamldecode(file("${path.module}/../devgen/models.yaml"))

  # Every model any tier can reach, with any inference-profile prefix removed.
  approved_models = distinct([
    for tier in local.devgen_config.tiers :
    trimprefix(tier.model, "us.")
  ])

  foundation_model_arns = [
    for model in local.approved_models :
    "arn:aws:bedrock:*::foundation-model/${model}"
  ]

  inference_profile_arns = [
    for model in local.approved_models :
    "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/us.${model}"
  ]
}

resource "aws_iam_policy" "devgen_invoke" {
  name        = "${var.project_name}-invoke"
  description = "Invoke only the models listed in devgen/models.yaml."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeApprovedModels"
        Effect = "Allow"
        Action = ["bedrock:Converse"]
        Resource = concat(
          local.foundation_model_arns,
          local.inference_profile_arns,
        )
      },
      {
        Sid      = "ApplyGuardrail"
        Effect   = "Allow"
        Action   = "bedrock:ApplyGuardrail"
        Resource = aws_bedrock_guardrail.devgen.guardrail_arn
      },
      {
        Sid      = "ReadDevgenConfig"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.guardrail.arn
      },
    ]
  })
}
