data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  # Must match the bucket in backend.tf.
  state_bucket = var.state_bucket_name
}

resource "aws_iam_role" "ci" {
  name = "${var.project_name}-ci"

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
          # Immutable sub format for repos created after 2026-07-15.
          # The numeric ids survive renames - that is the point of the format.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })
}

# terraform plan reads existing resources across many services.
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
      Resource = "arn:aws:s3:::${local.state_bucket}/devgen/*"
    }]
  })
}

# Same policy engineers get: only the models in models.yaml.
resource "aws_iam_role_policy_attachment" "ci_invoke" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.devgen_invoke.arn
}