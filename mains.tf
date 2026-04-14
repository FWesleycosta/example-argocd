variable "name" {
  description = "Nome da REST API"
  type        = string

  validation {
    condition     = length(var.name) > 0
    error_message = "O nome da REST API não pode ser vazio."
  }
}

variable "description" {
  description = "Descrição da REST API"
  type        = string
  default     = null
}

variable "endpoint_type" {
  description = "Tipo do endpoint da API. Valores válidos: EDGE, REGIONAL, PRIVATE"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["EDGE", "REGIONAL", "PRIVATE"], var.endpoint_type)
    error_message = "endpoint_type deve ser EDGE, REGIONAL ou PRIVATE."
  }
}

variable "vpc_endpoint_id" {
  description = "ID do VPC Endpoint para APIs do tipo PRIVATE"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags a serem aplicadas à REST API"
  type        = map(string)
  default     = {}
}

