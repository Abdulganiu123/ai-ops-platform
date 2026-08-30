resource "aws_s3_bucket" "knowledge" {
  # checkov:skip=CKV_AWS_18: access logging needs a second bucket that fails the same checks
  # checkov:skip=CKV_AWS_144: cross-region replication is DR beyond scope
  # checkov:skip=CKV_AWS_145: SSE-S3 enabled; contents are our own published postmortems
  # checkov:skip=CKV2_AWS_62: event notifications need an SNS/SQS/Lambda target
  # checkov:skip=CKV2_AWS_61: the index is one overwritten object, no versions accumulate
  bucket = "${var.project_name}-knowledge-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "knowledge" {
  bucket                  = aws_s3_bucket.knowledge.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge" {
  bucket = aws_s3_bucket.knowledge.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_policy" "devgen_knowledge" {
  name        = "${var.project_name}-knowledge"
  description = "Embed text and read or write the incident index."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EmbedText"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Sid      = "ReadWriteIndex"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.knowledge.arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "diagnose_knowledge" {
  role       = aws_iam_role.diagnose.name
  policy_arn = aws_iam_policy.devgen_knowledge.arn
}

resource "aws_ssm_parameter" "knowledge_bucket" {
  # checkov:skip=CKV2_AWS_34: a bucket name is not a credential
  name  = "/${var.project_name}/knowledge-bucket"
  type  = "String"
  value = aws_s3_bucket.knowledge.id
}
