resource "aws_sns_topic" "diagnosis" {
  name              = "${var.project_name}-diagnosis"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.diagnosis.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

# CloudWatch invokes this function asynchronously. Without a DLQ, a failed
# invocation is retried twice and then discarded with no trace.
resource "aws_sqs_queue" "diagnose_dlq" {
  name                      = "${var.project_name}-diagnose-dlq"
  message_retention_seconds = 1209600 # 14 days, the SQS maximum
  sqs_managed_sse_enabled   = true
}

resource "aws_iam_role" "diagnose" {
  name                 = "${var.project_name}-diagnose"
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/${var.project_name}-ci-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The same invoke policy engineers and CI get: only the models in models.yaml.
resource "aws_iam_role_policy_attachment" "diagnose_invoke" {
  role       = aws_iam_role.diagnose.name
  policy_arn = aws_iam_policy.devgen_invoke.arn
}

resource "aws_iam_role_policy_attachment" "diagnose_xray" {
  role       = aws_iam_role.diagnose.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
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
      {
        Sid      = "SendToDLQ"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.diagnose_dlq.arn
      },
    ]
  })
}

resource "aws_lambda_function" "diagnose" {
  # checkov:skip=CKV_AWS_173: the only env var is a non-secret SNS topic ARN; AWS-managed encryption at rest already applies
  # checkov:skip=CKV_AWS_272: code signing needs an AWS Signer profile and pipeline; disproportionate where branch-protected CI is the only deploy path
  # checkov:skip=CKV_AWS_117: deliberately outside the VPC - see docs/design.md. No VPC-only dependencies, and private placement needs four interface endpoints (~$28/month)
  function_name                  = "${var.project_name}-diagnose"
  role                           = aws_iam_role.diagnose.arn
  handler                        = "devgen.lambda_handler.handler"
  runtime                        = "python3.12"
  timeout                        = 120
  memory_size                    = 512
  reserved_concurrent_executions = 2
  filename                       = "${path.module}/../build/devgen-lambda.zip"
  source_code_hash               = filebase64sha256("${path.module}/../build/devgen-lambda.zip")

  dead_letter_config {
    target_arn = aws_sqs_queue.diagnose_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ALERT_TOPIC_ARN = aws_sns_topic.diagnosis.arn
    }
  }
}

