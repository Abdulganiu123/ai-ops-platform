# The CI role is created in terraform/bootstrap. We look it up and attach
# the policies this configuration owns, so a destroy here removes only the
# attachments, never the role itself.
data "aws_iam_role" "ci" {
  name = "${var.project_name}-ci"
}

resource "aws_iam_role_policy_attachment" "ci_invoke" {
  role       = data.aws_iam_role.ci.name
  policy_arn = aws_iam_policy.devgen_invoke.arn
}