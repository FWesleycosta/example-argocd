################################################################################
# AWS Step Functions - State Machine
################################################################################

resource "aws_sfn_state_machine" "this" {
  name     = var.name
  role_arn = aws_iam_role.step_functions.arn

  definition = var.definition

  type = var.type

  dynamic "logging_configuration" {
    for_each = var.logging_configuration != null ? [var.logging_configuration] : []

    content {
      log_destination        = "${logging_configuration.value.log_group_arn}:*"
      include_execution_data = logging_configuration.value.include_execution_data
      level                  = logging_configuration.value.level
    }
  }

  dynamic "tracing_configuration" {
    for_each = var.tracing_enabled ? [true] : []

    content {
      enabled = true
    }
  }

  tags = merge(
    var.tags,
    {
      "ManagedBy" = "Terraform"
    },
  )
}

################################################################################
# CloudWatch Log Group (optional)
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = var.create_log_group ? 1 : 0

  name              = "/aws/states/${var.name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.kms_key_id

  tags = var.tags
}
