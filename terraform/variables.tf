variable "region" {
  description = "AWS region for all resources."
  type        = string

}

variable "project_name" {
  description = "Short name used as a prefix for resource names."
  type        = string

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
  default     = 365
}


variable "enable_vpc_endpoint" {
  description = "Create a PrivateLink endpoint for bedrock-runtime. Costs ~$7/month per AZ."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC to place the endpoint in. Required only when enable_vpc_endpoint is true."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnets for the endpoint's network interfaces."
  type        = list(string)
  default     = []
}

variable "enable_account_filter" {
  description = "Watch every log group in the account for errors."
  type        = bool
  default     = false
}

variable "excluded_log_groups" {
  description = "Log groups the filter must skip, to prevent recursion."
  type        = list(string)
  default     = ["/aws/bedrock/devgen"]
}

variable "filter_pattern" {
  description = "Which log lines fire the Lambda. Keep narrow."
  type        = string
  default     = "?ERROR ?Exception ?FATAL"
}