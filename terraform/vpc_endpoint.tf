# PrivateLink endpoint for Bedrock.
#
# Only affects traffic that originates insidethe VPC. While devgen runs from a
# laptop or a GitHub-hosted runner, though this changes nothing. It becomes more valuable when the diagnose path runs as
# a Lambda in a private subnet.
#
# Left off deliberately. Set enable_vpc_endpoint = true to test it.

data "aws_vpc" "selected" {
  count = var.enable_vpc_endpoint ? 1 : 0
  id    = var.vpc_id
}

resource "aws_security_group" "bedrock_endpoint" {
  count = var.enable_vpc_endpoint ? 1 : 0

  name        = "${var.project_name}-bedrock-endpoint"
  description = "Allows HTTPS from inside the VPC to the Bedrock endpoint."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected[0].cidr_block]
  }

  # No egress rules: the endpoint only responds, it never initiates.
}


resource "aws_vpc_endpoint" "bedrock_runtime" {
  count = var.enable_vpc_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type = "Interface"

  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.bedrock_endpoint[0].id]
  private_dns_enabled = true

  # Endpoint policy: even from inside the VPC, only the approved models.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:Converse",
      ]
      Resource = concat(
        local.foundation_model_arns,
        local.inference_profile_arns,
      )
    }]
  })

  tags = {
    Name = "${var.project_name}-bedrock-runtime"
  }
}
