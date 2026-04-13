variable "name" {
  description = "The name of the secret."
  type        = string

  validation {
    condition     = length(var.name) > 0
    error_message = "The secret name must not be empty."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.name))
    error_message = "The secret name can only contain alphanumeric characters and the characters /_+=.@-"
  }
}

variable "description" {
  description = "A description for the secret."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before deleting the secret. Valid values: 0 (force delete) or between 7 and 30."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (force delete) or between 7 and 30."
  }
}

variable "initial_secret_string" {
  description = "Initial value for the secret. After creation, Terraform will ignore changes so external updates are preserved."
  type        = string
  default     = "{}"
  sensitive   = true
}

variable "tags" {
  description = "A map of tags to assign to the secret."
  type        = map(string)
  default     = {}
}


output "secret_id" {
  description = "The ID of the secret."
  value       = aws_secretsmanager_secret.this.id
}

output "secret_arn" {
  description = "The ARN of the secret."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "The name of the secret."
  value       = aws_secretsmanager_secret.this.name
}

output "secret_version_id" {
  description = "The version ID of the initial secret value."
  value       = aws_secretsmanager_secret_version.this.version_id
}



