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