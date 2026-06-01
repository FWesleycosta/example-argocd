variable "app_name" {
    description = "Nome da aplicação (vem do repositório)"
    type = string
}

variable "namespace" {
    description = "Nome do namespace onde a aplicação vai rodar no EKS"
    type = string
}

variable "alb_shared_dns" {
  type    = string
}

variable "api_gateway_vpc_link" {
  type    = string
}

variable "alb_shared_listener" {
  type    = string
}

variable "domain_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "base_path" {
  type = string
}

variable "api_type" {
  description = "public or private"
  type = string
  default = "private"
}

variable "vpc_endpoint_apigw" {
  type    = string
}

variable "domain_internal_name" {
  type = string
}

variable "domain_name_id" {
  type = string
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ssm_parameters" {
  type = string
  default = "[]"
}

variable "dynamodb_tables" {
  description = "Lista de tabelas DynamoDB a serem criadas"
  type = list(object({
    table_name               = string
    billing_mode             = optional(string, "PAY_PER_REQUEST")
    hash_key                 = string
    range_key                = optional(string)
    attributes               = list(object({ name = string, type = string }))
    global_secondary_indexes = optional(list(object({
      name               = string
      hash_key           = string
      range_key          = optional(string)
      projection_type    = optional(string, "ALL")
      non_key_attributes = optional(list(string))
      read_capacity      = optional(number)
      write_capacity     = optional(number)
    })), [])
  }))
  default = []
}

variable "s3_buckets" {
  description = "Lista de buckets S3 a serem criados"
  type = string
  default = "[]"
}

variable "secrets" {
  type = list(object({
    name          = string
    description   = optional(string, "")
    keys          = list(string)
    compartilhado = optional(string, "false")
  }))
  default = []
}

variable "cognito" {
  type = string
  default = "false"
  description = "Se true, adiciona permissões do Cognito B2C à policy"
}
