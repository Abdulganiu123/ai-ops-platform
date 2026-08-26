variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names."
  type        = string
  default     = "devgen"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket for Terraform state."
  type        = string
}

variable "github_repo" {
  description = "Repo allowed to assume the CI role, in the immutable owner@id/repo@id form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._@-]+/[A-Za-z0-9._@-]+$", var.github_repo))
    error_message = "Use owner/name or owner@id/name@id. Not a URL."
  }
}