################################################################################
# Outputs
################################################################################

output "state_machine_arn" {
  description = "ARN da State Machine"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_id" {
  description = "ID da State Machine"
  value       = aws_sfn_state_machine.this.id
}

output "state_machine_name" {
  description = "Nome da State Machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "ARN da IAM Role do Step Functions"
  value       = aws_iam_role.step_functions.arn
}

output "role_name" {
  description = "Nome da IAM Role do Step Functions"
  value       = aws_iam_role.step_functions.name
}

output "log_group_arn" {
  description = "ARN do CloudWatch Log Group (se criado)"
  value       = try(aws_cloudwatch_log_group.this[0].arn, null)
}
