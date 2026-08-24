resource "aws_sns_topic" "diagnosis" {
  name = "${var.project_name}-diagnosis"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.diagnosis.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

resource "aws_iam_role" "diagnose" {
  name = "${var.project_name}-diagnose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Same invoke policy engineers get: only the models in models.yaml.
resource "aws_iam_role_policy_attachment" "diagnose_invoke" {
  role       = aws_iam_role.diagnose.name
  policy_arn = aws_iam_policy.devgen_invoke.arn
}

resource "aws_iam_role_policy" "diagnose_extra" {
  name = "read-logs-and-notify"
  role = aws_iam_role.diagnose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:*"
      },
      {
        Sid      = "ReadLogsToDiagnose"
        Effect   = "Allow"
        Action   = ["logs:FilterLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:log-group:*"
      },
      {
        Sid      = "Notify"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.diagnosis.arn
      },
    ]
  })
}

resource "aws_lambda_function" "diagnose" {
  reserved_concurrent_executions = 2
  function_name                  = "${var.project_name}-diagnose"
  role                           = aws_iam_role.diagnose.arn
  handler                        = "devgen.lambda_handler.handler"
  runtime                        = "python3.12"
  timeout                        = 120
  memory_size                    = 512
  filename                       = "${path.module}/../build/devgen-lambda.zip"
  source_code_hash               = filebase64sha256("${path.module}/../build/devgen-lambda.zip")

  environment {
    variables = {
      ALERT_TOPIC_ARN = aws_sns_topic.diagnosis.arn
    }
  }
}

