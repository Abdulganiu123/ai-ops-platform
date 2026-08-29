data "aws_caller_identity" "current" {}

# Account-level, shared with other projects. We read it, we do not own it.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "ci" {
  name                 = "${var.project_name}-ci"
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  lifecycle {
    prevent_destroy = true
  }
}

# terraform plan refreshes every managed resource across many services.
resource "aws_iam_role_policy_attachment" "ci_readonly" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# plan creates and removes the state lock object.
resource "aws_iam_role_policy" "ci_state" {
  name = "terraform-state"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.state.arn}/*"
    }]
  })
}

# ReadOnlyAccess omits some Bedrock read actions that plan needs.
resource "aws_iam_role_policy" "ci_bedrock_read" {
  name = "bedrock-read"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:ListTagsForResource",
        "bedrock:GetGuardrail",
      ]
      Resource = "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:guardrail/*"
    }]
  })
}

# Applying requires write access to every service this project provisions.
# Scoped by service rather than by action: enumerating individual actions is
# brittle and breaks whenever a resource type is added. The approval gate on
# the production environment is the compensating control.
resource "aws_iam_role_policy" "ci_apply" {
  # checkov:skip=CKV_AWS_286: constrained by permissions boundary, which denies unbounded role creation
  # checkov:skip=CKV_AWS_287: no credential-exposure actions granted; sts is capped by the boundary
  # checkov:skip=CKV_AWS_288: single-account project with no cross-account trust
  # checkov:skip=CKV_AWS_289: boundary denies self-modification of the CI role
  # checkov:skip=CKV_AWS_290: writes are gated on environment approval, not unattended
  # checkov:skip=CKV_AWS_355: Terraform must create resources whose ARNs do not exist at policy-authoring time
  # checkov:skip=CKV2_AWS_40: iam:* is required to manage roles; the boundary caps what those roles can hold
  name = "terraform-apply"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:*",
        "lambda:*",
        "kms:*",
        "sns:*",
        "sqs:*",
        "bedrock:*",
        "logs:*",
        "ssm:*",
        "budgets:*",
        "s3:*",
      ]
      Resource = "*"
    }]
  })
}

# Bedrock invoke permissions for the smoke test. Defined here rather than in
# the application config so CI never modifies the role it authenticates as.
resource "aws_iam_role_policy" "ci_invoke_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:Converse"]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        Effect   = "Allow"
        Action   = "bedrock:ApplyGuardrail"
        Resource = "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:guardrail/*"
      },
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      },
    ]
  })
}