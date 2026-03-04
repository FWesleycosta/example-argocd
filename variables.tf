variable "pipe_name" {
  description = "Nome do EventBridge Pipe."
  type        = string
}

variable "desired_state" {
  description = "Estado desejado do Pipe. RUNNING ou STOPPED."
  type        = string
  default     = "RUNNING"

  validation {
    condition     = contains(["RUNNING", "STOPPED"], var.desired_state)
    error_message = "desired_state deve ser RUNNING ou STOPPED."
  }
}


variable "source_arn" {
  description = "ARN do recurso de origem (SQS, DynamoDB Stream, Kinesis Stream)."
  type        = string
}

variable "source_parameters" {
  description = <<-EOT
    Parâmetros do source. Preencha apenas o bloco correspondente ao tipo de source.
    - sqs:      batch_size, maximum_batching_window_in_seconds
    - dynamodb: starting_position (TRIM_HORIZON | LATEST), batch_size
    - kinesis:  starting_position (TRIM_HORIZON | LATEST | AT_TIMESTAMP), batch_size
  EOT
  type = object({
    sqs = optional(object({
      batch_size                         = optional(number, 10)
      maximum_batching_window_in_seconds = optional(number, 0)
    }))
    dynamodb = optional(object({
      starting_position = string
      batch_size        = optional(number, 10)
    }))
    kinesis = optional(object({
      starting_position = string
      batch_size        = optional(number, 10)
    }))
  })
  default = {}
}

variable "target_arn" {
  description = "ARN do recurso de destino (Step Functions, Lambda, SQS, EventBus)."
  type        = string
}

variable "target_parameters" {
  description = <<-EOT
    Parâmetros do target. Preencha apenas o bloco correspondente ao tipo de target.
    - sfn:      invocation_type (FIRE_AND_FORGET | REQUEST_RESPONSE)
    - lambda:   invocation_type (FIRE_AND_FORGET | REQUEST_RESPONSE)
    - sqs:      message_group_id (obrigatório para FIFO)
    - eventbus: detail_type, source
  EOT
  type = object({
    sfn = optional(object({
      invocation_type = optional(string, "FIRE_AND_FORGET")
    }))
    lambda = optional(object({
      invocation_type = optional(string, "FIRE_AND_FORGET")
    }))
    sqs = optional(object({
      message_group_id = optional(string)
    }))
    eventbus = optional(object({
      detail_type = string
      source      = string
    }))
  })
  default = {}
}


variable "log_group_arn" {
  description = "ARN do CloudWatch Log Group para logs do Pipe. Null desativa os logs."
  type        = string
  default     = null
}

variable "log_level" {
  description = "Nível de log. ERROR, INFO ou TRACE."
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["ERROR", "INFO", "TRACE"], var.log_level)
    error_message = "log_level deve ser ERROR, INFO ou TRACE."
  }
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
