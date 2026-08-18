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
  description = "Se true, adiciona permissões do Cognito B2C à policy"
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
  description = "Minimum TLS security policy for the domain. Use a TLS_1_2 (or newer) policy for production workloads; TLS_1_0 is deprecated and should only be used for legacy clients that cannot be upgraded. Note that the available policies differ by endpoint_type: REGIONAL domains support the SecurityPolicy_TLS13_* / SecurityPolicy_TLS12_* values, while EDGE domains support the *_EDGE values and the legacy TLS_1_0 / TLS_1_2 aliases."
  type        = string
  default     = "SecurityPolicy_TLS13_1_3_2025_09"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_2", "SecurityPolicy_TLS13_1_3_2025_09", "SecurityPolicy_TLS13_1_3_FIPS_2025_09", "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_PQ_2025_09", "SecurityPolicy_TLS13_1_2_2021_06", "SecurityPolicy_TLS13_2025_EDGE", "SecurityPolicy_TLS12_PFS_2025_EDGE", "SecurityPolicy_TLS12_2018_EDGE"], var.security_policy)
    error_message = "security_policy must be one of the supported values: TLS_1_0, TLS_1_2, SecurityPolicy_TLS13_1_3_2025_09, SecurityPolicy_TLS13_1_3_FIPS_2025_09, SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_PQ_2025_09, SecurityPolicy_TLS13_1_2_2021_06, SecurityPolicy_TLS13_2025_EDGE, SecurityPolicy_TLS12_PFS_2025_EDGE, or SecurityPolicy_TLS12_2018_EDGE."
  }
}

variable "endpoint_access_mode" {
  description = "Endpoint access mode for the custom domain (BASIC or STRICT). Required by the newer SecurityPolicy_TLS13_*/SecurityPolicy_TLS12_* security policies; ignored for the legacy TLS_1_0/TLS_1_2 policies. BASIC keeps the standard behavior; STRICT enforces stricter TLS handling."
  type        = string
  default     = "STRICT"

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
    queue_name = string
    fifo_queue = optional(string, "false")
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

variable "project_name" {
  description = "Nome do projeto (vem do repositório)"
  type        = string
}

variable "lambda_functions" {
  description = <<-EOT
    Lista de funções Lambda a serem criadas. Vazia por padrão: quem não usa
    Lambda não paga nada em plan nem em recurso.

    O `function_name` informado aqui é o nome CURTO — a esteira prefixa com
    ambiente e região (lambda-<env>-<regiao>-<nome>), como já é feito em SQS
    e SNS.

    `role_arn` é opcional: sem ele, a função usa a role de execução criada
    pela própria esteira (`lambda-exec-<app_name>`), que já concede escrita no
    log group da função e, quando necessário, ENI de VPC e X-Ray. Informe um
    ARN só quando a função precisar de uma role própria com permissões extras.
  EOT

  type = list(object({
    function_name    = string
    handler          = string
    runtime          = string
    filename         = string
    source_code_hash = optional(string)

    description        = optional(string)
    memory_size        = optional(number, 128)
    timeout            = optional(number, 30)
    ephemeral_storage  = optional(number, 512)
    architectures      = optional(list(string), ["arm64"])
    environment        = optional(map(string))
    log_retention_days = optional(number, 30)
    tracing_config     = optional(string, "Active")
    publish            = optional(bool, true)

    subnet_ids         = optional(list(string))
    security_group_ids = optional(list(string))

    layers     = optional(list(object({ name = string, version = optional(number) })), [])
    layer_arns = optional(list(string), [])

    role_arn = optional(string)
  }))

  default = []
}
variable "resource_suffix" {
  description = <<-EOT
    Sufixo aplicado aos nomes de recursos que NÃO embutem o environment
    (IAM roles/policy, log group do API Gateway, nome da REST API, DynamoDB,
    Secrets, SSM e base_path). Vazio nos ambientes padrão — dev, hml e prd
    vivem em contas separadas e não colidem. No sandbox (branch sandbox/*),
    que compartilha a conta de DEV, a esteira envia '-sdx' para que os
    recursos coexistam com os de dev sem conflito de nome.
  EOT

  type    = string
  default = ""

  validation {
    condition     = var.resource_suffix == "" || can(regex("^-[a-z0-9-]+$", var.resource_suffix))
    error_message = "resource_suffix deve ser vazio ou iniciar com '-' seguido de [a-z0-9-] (ex.: '-sdx')."
  }
}
