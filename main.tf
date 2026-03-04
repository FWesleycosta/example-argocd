resource "aws_pipe_pipe" "this" {
  name          = var.pipe_name
  role_arn      = var.role_arn
  desired_state = var.desired_state

  source = var.source_arn
  source_parameters {
    dynamic "sqs_queue_parameters" {
      for_each = var.source_parameters.sqs != null ? [var.source_parameters.sqs] : []
      content {
        batch_size                         = sqs_queue_parameters.value.batch_size
        maximum_batching_window_in_seconds = sqs_queue_parameters.value.maximum_batching_window_in_seconds
      }
    }

    dynamic "dynamo_db_stream_parameters" {
      for_each = var.source_parameters.dynamodb != null ? [var.source_parameters.dynamodb] : []
      content {
        starting_position = dynamo_db_stream_parameters.value.starting_position
        batch_size        = dynamo_db_stream_parameters.value.batch_size
      }
    }

    dynamic "kinesis_stream_parameters" {
      for_each = var.source_parameters.kinesis != null ? [var.source_parameters.kinesis] : []
      content {
        starting_position = kinesis_stream_parameters.value.starting_position
        batch_size        = kinesis_stream_parameters.value.batch_size
      }
    }
  }

  target = var.target_arn
  target_parameters {
    dynamic "step_function_state_machine_parameters" {
      for_each = var.target_parameters.sfn != null ? [var.target_parameters.sfn] : []
      content {
        invocation_type = step_function_state_machine_parameters.value.invocation_type
      }
    }

    dynamic "lambda_function_parameters" {
      for_each = var.target_parameters.lambda != null ? [var.target_parameters.lambda] : []
      content {
        invocation_type = lambda_function_parameters.value.invocation_type
      }
    }

    dynamic "sqs_queue_parameters" {
      for_each = var.target_parameters.sqs != null ? [var.target_parameters.sqs] : []
      content {
        message_group_id = sqs_queue_parameters.value.message_group_id
      }
    }

    dynamic "event_bridge_event_bus_parameters" {
      for_each = var.target_parameters.eventbus != null ? [var.target_parameters.eventbus] : []
      content {
        detail_type = event_bridge_event_bus_parameters.value.detail_type
        source      = event_bridge_event_bus_parameters.value.source
      }
    }
  }

  dynamic "log_configuration" {
    for_each = var.log_group_arn != null ? [1] : []
    content {
      log_level = var.log_level
      cloudwatch_logs_log_destination {
        log_group_arn = var.log_group_arn
      }
    }
  }

  tags = local.tags
}
