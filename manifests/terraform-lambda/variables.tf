########################################
# Identidade — gerado pela esteira em _app.auto.tfvars.json
########################################

variable "app_name" {
  description = "Nome da aplicação (= Build.Repository.Name)."
  type        = string
}

variable "project_name" {
  description = "Projeto do Azure DevOps (= System.TeamProject). Só tag."
  type        = string
}

variable "function_name_prefix" {
  description = "Prefixo das funções: <prefix>-<handler><suffix>. A esteira envia lambda.function_name_prefix ou, vazio, o nome do repositório."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.function_name_prefix))
    error_message = "function_name_prefix aceita letras, números, '.', '_' e '-' (regra de nome de função Lambda)."
  }
}

variable "package_file" {
  description = "Caminho (relativo ao workdir) do zip publicado pelo stage Build. Um único pacote serve a todas as funções de lambda.handlers."
  type        = string
}

########################################
# Ambiente — _pipeline.auto.tfvars.json (deploy-lambda.yaml)
########################################

variable "environment" {
  description = "dev, hml, prd ou sdx."
  type        = string

  validation {
    condition     = contains(["dev", "hml", "prd", "sdx"], var.environment)
    error_message = "environment deve ser dev, hml, prd ou sdx."
  }
}

variable "aws_region" {
  type = string
}

variable "resource_suffix" {
  description = "Sufixo de sandbox (ex.: -sdx). Vazio fora do sandbox. Entra em todo nome que não embute o ambiente; SSM e secrets usam prefixo de caminho (ver locals)."
  type        = string
  default     = ""
  nullable    = false
}

variable "sistema" {
  description = "Sistema/domínio de negócio (tag de governança)."
  type        = string
  default     = ""
  nullable    = false
}

variable "owner" {
  description = "Time/pessoa responsável (tag de governança)."
  type        = string
  default     = ""
  nullable    = false
}

variable "subnet_ids_csv" {
  description = "Subnets privadas separadas por vírgula (variables/env/<env>.yaml: subnetsPrivate). Vazio = função fora da VPC."
  type        = string
  default     = ""
  nullable    = false
}

variable "vpc_id" {
  description = "VPC das subnets acima. Obrigatório quando subnet_ids_csv não é vazio."
  type        = string
  default     = ""
  nullable    = false
}

########################################
# `lambda` — objeto do stack (chaves da esteira, como src_path, são ignoradas aqui)
########################################

variable "lambda" {
  description = "handlers é obrigatório; o resto tem default. Todas as funções compartilham runtime, pacote, role, sizing e env vars."
  type = object({
    handlers           = map(string)
    runtime            = optional(string, "dotnet10")
    architecture       = optional(string, "x86_64")
    memory_size        = optional(number, 512)
    timeout            = optional(number, 30)
    tracing_config     = optional(string, "PassThrough")
    description        = optional(string, "")
    log_retention_days = optional(number, 30)
    layer_arns         = optional(list(string), [])
  })

  validation {
    condition     = length(var.lambda.handlers) > 0
    error_message = "lambda.handlers não pode ser vazio: declare ao menos uma função (<chave>: <Assembly::Tipo::Metodo>)."
  }

  validation {
    condition     = alltrue([for k, _ in var.lambda.handlers : can(regex("^[a-z0-9][a-z0-9-]*$", k))])
    error_message = "Chaves de lambda.handlers aceitam só minúsculas, dígitos e '-' (ex.: salvar-pg)."
  }

  validation {
    condition     = can(regex("^(dotnet|python|nodejs|java|ruby|provided)[a-z0-9.]*$", var.lambda.runtime))
    error_message = "lambda.runtime inválido (esperado algo como dotnet10, python3.12, nodejs20.x)."
  }

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda.architecture)
    error_message = "lambda.architecture deve ser x86_64 ou arm64 (a esteira deriva o RID do dotnet publish daqui)."
  }

  validation {
    condition     = var.lambda.memory_size >= 128 && var.lambda.memory_size <= 10240
    error_message = "lambda.memory_size deve estar entre 128 e 10240 MB."
  }

  validation {
    condition     = var.lambda.timeout >= 1 && var.lambda.timeout <= 900
    error_message = "lambda.timeout deve estar entre 1 e 900 segundos."
  }

  validation {
    condition     = contains(["Active", "PassThrough"], var.lambda.tracing_config)
    error_message = "lambda.tracing_config deve ser Active ou PassThrough."
  }
}

# As três listas abaixo são `any` de propósito: quando o app omite a chave em `config`, o Azure
# DevOps entrega "" (e não null), e uma lista tipada rejeitaria. Os locals saneiam para [].

variable "release_version" {
  description = "Build.BuildId da esteira. Vira DD_VERSION quando o tracing Datadog está habilitado."
  type        = string
  default     = ""
}

variable "datadog" {
  description = <<-EOT
    Tracing APM via Datadog Lambda Extension (só trace: logs e enhanced metrics desligados).
    A esteira só habilita em prd (stages/deploy-lambda.yaml); dev/hml/sdx chegam com enabled=false
    e não recebem layer nem variável DD_*. Valores vêm de variables/env/prd.yaml.
  EOT
  type = object({
    enabled                 = optional(bool, false)
    site                    = optional(string, "")
    api_key_secret_arn      = optional(string, "")
    extension_layer_version = optional(number, 0)
    tracer_layer_version    = optional(number, 0)
  })
  default = {}

  validation {
    condition = !var.datadog.enabled || (
      var.datadog.site != "" &&
      can(regex("^arn:aws:secretsmanager:", var.datadog.api_key_secret_arn)) &&
      var.datadog.extension_layer_version > 0 &&
      var.datadog.tracer_layer_version > 0
    )
    error_message = "datadog.enabled exige site, api_key_secret_arn (ARN do Secrets Manager) e versões > 0 das layers Extension e do tracer do runtime (variables/env/prd.yaml: datadogSite, datadogApiKeySecretArn, datadogExtensionLayerVersion, datadogTracerLayerVersion{Dotnet,Node,Python})."
  }
}

variable "environment_variables_common" {
  description = "Env vars iguais nos três ambientes (config.env_vars): lista de {name, value}."
  type        = any
  default     = []
  nullable    = false
}

variable "environment_variables_env" {
  description = "Env vars do ambiente do stage (config.env_vars_by_env.<env>); sobrescrevem as comuns de mesmo nome."
  type        = any
  default     = []
  nullable    = false
}

variable "ssm_parameters" {
  description = "config.ssm_parameters.<env>: lista de {name, value, type?, description?}. Aceita JSON string (como o backend)."
  type        = any
  default     = []
  nullable    = false
}

########################################
# `resources` — objeto do stack; toda chave é opcional
########################################

variable "resources" {
  description = "Recursos AWS do app. Nomes de fila/tópico são lógicos: o root aplica sqs-<env>-<region>-<nome><suffix> / sns-...; referência a nome não declarado aqui vira lookup externo (sem sufixo)."
  type = object({
    sqs = optional(list(object({
      queue_name                 = string
      fifo_queue                 = optional(bool, false)
      dlq_queue_name             = optional(string, "")
      max_receive_count          = optional(number, 3)
      visibility_timeout_seconds = optional(number, 60)
      message_retention_seconds  = optional(number, 86400)
      receive_wait_time_seconds  = optional(number, 20)
    })), [])

    sns_topics = optional(list(object({
      topic_name                  = string
      fifo_topic                  = optional(bool, false)
      content_based_deduplication = optional(bool, false)
    })), [])

    # O tópico pode ser externo; a fila precisa estar em sqs (a policy da fila é criada aqui).
    sns_sqs_subscriptions = optional(list(object({
      topic_name          = string
      queue_name          = string
      filter_policy       = optional(any, null)
      filter_policy_scope = optional(string, "MessageAttributes")
    })), [])

    # Segredos criados vazios (chaves com PREENCHER); o valor é preenchido fora da esteira.
    secrets = optional(list(object({
      name        = string
      description = optional(string, "")
      keys        = list(string)
    })), [])

    # Event source mapping SQS -> função (queue_name gerenciada ou externa).
    sqs_triggers = optional(list(object({
      handler                            = string
      queue_name                         = string
      batch_size                         = optional(number, 10)
      maximum_batching_window_in_seconds = optional(number, 0)
      enabled                            = optional(bool, true)
      report_batch_item_failures         = optional(bool, false)
    })), [])

    # definition_file: ASL em infra/ do app, renderizado com templatefile (ver README).
    step_functions = optional(list(object({
      name            = string
      definition_file = string
      type            = optional(string, "STANDARD")
    })), [])

    # EventBridge Pipe fila (gerenciada) -> state machine (gerenciada).
    pipes = optional(list(object({
      name                 = string
      source_queue         = string
      target_step_function = string
      batch_size           = optional(number, 1)
      invocation_type      = optional(string, "FIRE_AND_FORGET")
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(distinct([for q in var.resources.sqs : q.queue_name])) == length(var.resources.sqs)
    error_message = "resources.sqs: queue_name repetido."
  }

  validation {
    condition     = alltrue([for s in var.resources.step_functions : contains(["STANDARD", "EXPRESS"], s.type)])
    error_message = "resources.step_functions[].type deve ser STANDARD ou EXPRESS."
  }

  validation {
    condition     = alltrue([for p in var.resources.pipes : contains(["FIRE_AND_FORGET", "REQUEST_RESPONSE"], p.invocation_type)])
    error_message = "resources.pipes[].invocation_type deve ser FIRE_AND_FORGET ou REQUEST_RESPONSE."
  }
}

variable "definitions_dir" {
  description = "Diretório (relativo ao root) com os ASL das step functions. A esteira copia infra/*.asl.json do app para cá."
  type        = string
  default     = "definitions"
  nullable    = false
}
