resource "aws_bedrock_guardrail" "devgen" {
  name        = "${var.project_name}-guardrail"
  description = "Content and PII controls for the devgen CLI."

  blocked_input_messaging   = "This request was blocked by the devgen guardrail."
  blocked_outputs_messaging = "The response was blocked by the devgen guardrail."

  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }

    filters_config {
      type            = "HATE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }

    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }

  sensitive_information_policy_config {
    # Credentials - BLOCK. If one reaches here, redact.py failed and we
    # want a loud stop, not a quiet mask.
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_SECRET_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "BLOCK"
    }

    # Personal data - ANONYMIZE. Appears incidentally in logs and should
    # not stop the diagnosis.
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "ADDRESS"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "USERNAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "IP_ADDRESS"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_CVV"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "DRIVER_ID"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_PASSPORT_NUMBER"
      action = "ANONYMIZE"
    }
  }
}
