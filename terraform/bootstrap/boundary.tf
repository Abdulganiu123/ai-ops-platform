locals {
  # Built as strings rather than referenced, to avoid a dependency cycle:
  # the role needs the boundary, and the boundary refers to the role.
  ci_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-ci"
  boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-ci-boundary"
}


# A ceiling on what the CI role can ever do, regardless of what policies
# are attached to it. The inline apply policy grants; this constrains.
resource "aws_iam_policy" "ci_boundary" {
  # This is a permissions BOUNDARY, not an identity policy. Attached via
  # permissions_boundary, its Allow statements define a ceiling and grant
  # nothing. Checkov evaluates every aws_iam_policy as if it were granting,
  # so these findings invert the resource's actual purpose - this policy is
  # what prevents privilege escalation.
  # checkov:skip=CKV_AWS_286: this policy denies privilege escalation, it does not permit it
  # checkov:skip=CKV_AWS_287: boundary caps credential actions rather than granting them
  # checkov:skip=CKV_AWS_288: single-account project; DenyAccountLevelChanges blocks org access
  # checkov:skip=CKV_AWS_289: DenySelfModification is the constraint this check asks for
  # checkov:skip=CKV_AWS_290: a ceiling grants no write access on its own
  # checkov:skip=CKV_AWS_355: a boundary must cover services generally to function as a ceiling
  # checkov:skip=CKV2_AWS_40: iam:* here is the maximum permitted, narrowed by the Deny statements below
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
        # CI must not be able to remove its ceiling or delete itself.
        Sid    = "DenySelfDestruction"
        Effect = "Deny"
        Action = [
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
        ]
        Resource = local.ci_role_arn
      },
      {
        # Attaching to the CI role is allowed, but only policies this project
        # owns. Blocks attaching AdministratorAccess or any AWS managed policy.
        Sid      = "DenyAttachingForeignPolicies"
        Effect   = "Deny"
        Action   = ["iam:AttachRolePolicy"]
        Resource = local.ci_role_arn
        Condition = {
          ArnNotLike = {
            "iam:PolicyARN" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-*"
          }
        }
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