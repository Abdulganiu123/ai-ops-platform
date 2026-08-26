resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_18: access logging needs a second bucket that fails the same checks
  # checkov:skip=CKV_AWS_144: cross-region replication is DR beyond scope for one account
  # checkov:skip=CKV_AWS_145: SSE-S3 enabled; state holds no customer data
  # checkov:skip=CKV2_AWS_62: event notifications need an SNS/SQS/Lambda target
  bucket = var.state_bucket_name

  # The whole point of this restructure. Refuses to delete even if someone
  # runs destroy in this directory.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}