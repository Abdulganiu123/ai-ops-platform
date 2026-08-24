

resource "aws_lambda_permission" "logs" {
  count = var.enable_account_filter ? 1 : 0

  statement_id   = "AllowCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.diagnose.function_name
  principal      = "logs.amazonaws.com"
  source_arn     = "arn:aws:logs:${var.region}:${local.account_id}:log-group:*"
  source_account = local.account_id
}

resource "aws_cloudwatch_log_account_policy" "errors" {
  count = var.enable_account_filter ? 1 : 0

  policy_name = "${var.project_name}-error-subscription"
  policy_type = "SUBSCRIPTION_FILTER_POLICY"
  scope       = "ALL"

  # Exclude anything in the delivery path, or logs about logs become logs.
  selection_criteria = "LogGroupName NOT IN ${jsonencode(var.excluded_log_groups)}"

  policy_document = jsonencode({
    DestinationArn = aws_lambda_function.diagnose.arn
    FilterPattern  = var.filter_pattern
    Distribution   = "Random"
  })

  depends_on = [aws_lambda_permission.logs]
}