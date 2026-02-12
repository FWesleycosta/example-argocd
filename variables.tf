################################################################################
# Required Variables
################################################################################

variable "name" {
  description = "Nome da State Machine"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 80
    error_message = "O nome deve ter entre 1 e 80 caracteres."
  }
}

variable "definition" {
  description = "Definição da State Machine em JSON (Amazon States Language)"
  type        = string

  validation {
    condition     = can(jsondecode(var.definition))
    error_message = "A definição deve ser um JSON válido."
  }
}

################################################################################
# Optional Variables
################################################################################

variable "type" {
  description = "Tipo da State Machine: STANDARD ou EXPRESS"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.type)
    error_message = "O tipo deve ser STANDARD ou EXPRESS."
  }
}

variable "tags" {
  description = "Tags a serem aplicadas em todos os recursos"
  type        = map(string)
  default     = {}
}

variable "additional_policy_arns" {
  description = "Lista de ARNs de políticas IAM adicionais para anexar à role do Step Functions"
  type        = list(string)
  default     = []
}

################################################################################
# Logging
################################################################################

variable "create_log_group" {
  description = "Se deve criar um CloudWatch Log Group para a State Machine"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Dias de retenção dos logs no CloudWatch"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "O valor de retenção deve ser um dos valores aceitos pelo CloudWatch."
  }
}

variable "logging_configuration" {
  description = "Configuração de logging da State Machine"
  type = object({
    log_group_arn          = string
    include_execution_data = optional(bool, true)
    level                  = optional(string, "ERROR")
  })
  default = null

  validation {
    condition     = var.logging_configuration == null || contains(["ALL", "ERROR", "FATAL", "OFF"], try(var.logging_configuration.level, "ERROR"))
    error_message = "O nível de log deve ser ALL, ERROR, FATAL ou OFF."
  }
}

variable "kms_key_id" {
  description = "ARN da chave KMS para encriptar os logs"
  type        = string
  default     = null
}

################################################################################
# Tracing
################################################################################

variable "tracing_enabled" {
  description = "Habilitar X-Ray tracing na State Machine"
  type        = bool
  default     = false
}
