variable "app_name" {
  description = "Nome da aplicação (vem do repositório)"
  type        = string
}

variable "namespace" {
  description = "Nome do namespace onde a aplicação vai rodar no EKS"
  type        = string
}

variable "alb_shared_dns" {
  type = string
}

variable "api_gateway_vpc_link" {
  type = string
}

variable "alb_shared_listener" {
  type = string
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
  type        = string
  default     = "private"
}

variable "vpc_endpoint_apigw" {
  type = string
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
  type    = any
  default = []
}

variable "dynamodb_tables" {
  description = "Lista de tabelas DynamoDB a serem criadas"
  type = list(object({
    table_name   = string
    billing_mode = optional(string, "PAY_PER_REQUEST")
    hash_key     = string
    range_key    = optional(string)
    # Quando definido (ex.: "ttl"), habilita TTL na tabela apontando para esse atributo numérico (epoch em segundos).
    ttl_attribute_name = optional(string)
    attributes         = list(object({ name = string, type = string }))
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
  type        = any
  default     = []
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
  type        = string
  default     = "false"
  description = "Se true/True, adiciona permissões do Cognito B2C à policy (comparação case-insensitive)"
}

variable "endpoint_type" {
  description = "Domain endpoint type: REGIONAL (recommended) or EDGE."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "EDGE"], var.endpoint_type)
    error_message = "endpoint_type must be 'REGIONAL' or 'EDGE'."
  }
}

variable "security_policy" {
  description = "Minimum TLS security policy for the domain. Use a TLS_1_2 (or newer) policy for production workloads; TLS_1_0 is deprecated and should only be used for legacy clients that cannot be upgraded. Note that the available policies differ by endpoint_type: REGIONAL domains support the SecurityPolicy_TLS13_* / SecurityPolicy_TLS12_* values, while EDGE domains support the *_EDGE values and the legacy TLS_1_0 / TLS_1_2 aliases. O default aceita TLS 1.2 E 1.3 (PFS + pos-quantica) para nao quebrar clientes TLS 1.2 existentes; TLS 1.3-only (SecurityPolicy_TLS13_1_3_2025_09) e opt-in por app, apos validar $context.tlsVersion nos access logs."
  type        = string
  default     = "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_2", "SecurityPolicy_TLS13_1_3_2025_09", "SecurityPolicy_TLS13_1_3_FIPS_2025_09", "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_PQ_2025_09", "SecurityPolicy_TLS13_1_2_2021_06", "SecurityPolicy_TLS13_2025_EDGE", "SecurityPolicy_TLS12_PFS_2025_EDGE", "SecurityPolicy_TLS12_2018_EDGE"], var.security_policy)
    error_message = "security_policy must be one of the supported values: TLS_1_0, TLS_1_2, SecurityPolicy_TLS13_1_3_2025_09, SecurityPolicy_TLS13_1_3_FIPS_2025_09, SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_PQ_2025_09, SecurityPolicy_TLS13_1_2_2021_06, SecurityPolicy_TLS13_2025_EDGE, SecurityPolicy_TLS12_PFS_2025_EDGE, or SecurityPolicy_TLS12_2018_EDGE."
  }
}

variable "endpoint_access_mode" {
  description = "Endpoint access mode (BASIC or STRICT). Required by the newer SecurityPolicy_TLS13_*/SecurityPolicy_TLS12_* security policies; ignored for the legacy TLS_1_0/TLS_1_2 policies. STRICT impoe SNI host matching: invocar API privada sem custom domain/private DNS (ex.: URL do VPC endpoint com header Host) QUEBRA. Migracao recomendada pela AWS: enhanced policy + BASIC -> validar access logs -> STRICT (opt-in por app; voltar de STRICT para BASIC custa ~15 min de indisponibilidade)."
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["BASIC", "STRICT"], var.endpoint_access_mode)
    error_message = "endpoint_access_mode must be 'BASIC' or 'STRICT'."
  }
}

variable "certificate_arn" {
  type = string
}

variable "queue_name" {
  type = list(object({
    queue_name        = string
    fifo_queue        = optional(string, "false")
    dlq_queue_name    = optional(string, "")
    max_receive_count = optional(number, 3)
  }))
  default = []
}


variable "topic_name" {
  type = list(object({
    topic_name                  = string
    fifo_topic                  = optional(string, "false")
    content_based_deduplication = optional(string, "false")
  }))
  default = []
}


variable "sns_sqs_subscriptions" {
  description = "Assinaturas que ligam um tópico SNS (topic_name) a uma fila SQS (queue_name), ambos declarados em topic_name/queue_name."
  type = list(object({
    topic_name          = string
    queue_name          = string
    filter_policy       = optional(any, null)
    filter_policy_scope = optional(string, "MessageAttributes")
  }))
  default = []
}

variable "resource_suffix" {
  type    = string
  default = ""
}

variable "project_name" {
  description = "Nome do projeto (vem do repositório)"
  type        = string
}

variable "sistema" {
  description = "Sistema/dominio de negocio ao qual a aplicacao pertence (tag de governanca)"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Time/pessoa responsavel pela aplicacao (tag de governanca)"
  type        = string
  default     = ""
}
