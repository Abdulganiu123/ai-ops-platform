locals {
  # Built as strings rather than referenced, to avoid a dependency cycle:
  # the role needs the boundary, and the boundary refers to the role.
  ci_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-ci"
  boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-ci-boundary"
}


# A ceiling on what the CI role can ever do, regardless of what policies
# are attached to it. The inline apply policy grants; this constrains.
resource "aws_iam_policy" "ci_boundary" {
  name        = "${var.project_name}-ci-boundary"
  description = "Maximum permissions the CI role can ever hold."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProjectServices"
        Effect = "Allow"
        Action = [
          "iam:*", "lambda:*", "kms:*", "sns:*", "sqs:*",
          "bedrock:*", "logs:*", "ssm:*", "budgets:*",
          "s3:*", "sts:*", "xray:*", "ec2:Describe*",
        ]
        Resource = "*"
      },
      {
        # Privilege escalation: any role CI creates must carry this same
        # boundary, so it cannot mint an unbounded admin role.
        Sid      = "DenyCreatingUnboundedRoles"
        Effect   = "Deny"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = "*"
        Condition = {
                    StringNotEquals = {
            "iam:PermissionsBoundary" = local.boundary_arn
          }
        }
      },
      {
        Sid    = "DenySelfModification"
        Effect = "Deny"
        Action = [
          "iam:DeleteRolePermissionsBoundary",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
        ]
        Resource = local.ci_role_arn
      },
      {
        Sid      = "DenyStateBucketDeletion"
        Effect   = "Deny"
        Action   = ["s3:DeleteBucket"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid    = "DenyAccountLevelChanges"
        Effect = "Deny"
        Action = [
          "organizations:*",
          "account:*",
          "iam:CreateUser",
          "iam:CreateAccessKey",
        ]
        Resource = "*"
      },
    ]
  })
}