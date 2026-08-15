variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for resource names."
  type        = string
  default     = "devgen"
}

variable "monthly_budget_usd" {
  description = "Monthly Bedrock spend that triggers an alert."
  type        = number
  default     = 5
}

variable "budget_alert_email" {
  description = "Where budget alerts are sent."
  type        = string
}


variable "log_retention_days" {
  description = "How long to keep Bedrock invocation logs."
  type        = number
  default     = 30
}

variable "enable_vpc_endpoint" {
  description = "Create a PrivateLink endpoint for bedrock-runtime."
  type        = bool
  default     = false
}