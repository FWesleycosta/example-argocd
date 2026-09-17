locals {
  suffix = var.resource_suffix

  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
    Projeto   = var.project_name
    Sistema   = var.sistema
    Owner     = var.owner
  }

  ########################################
  # Funções
  ########################################

  # <prefix>-<handler><suffix>: o sufixo isola o sandbox (o nome não embute o ambiente).
  function_names = {
    for key, _ in var.lambda.handlers : key => "${var.function_name_prefix}-${key}${local.suffix}"
  }

  role_name = "lambda-${var.function_name_prefix}${local.suffix}"
  sg_name   = "${var.function_name_prefix}${local.suffix}-lambda"

  subnet_ids  = compact([for s in split(",", var.subnet_ids_csv) : trimspace(s)])
  vpc_enabled = length(local.subnet_ids) > 0

  # Hash só quando o pacote existe no workdir: permite plan/test sem o zip (hash nulo = sem diff de código).
  package_hash = fileexists(var.package_file) ? filebase64sha256(var.package_file) : null

  # "" / null / JSON string / lista -> lista de {name, value} (chave omitida no app chega como "").
  env_vars_common = try([for v in try(jsondecode(var.environment_variables_common), var.environment_variables_common) : { name = tostring(v.name), value = tostring(v.value) }], [])
  env_vars_env    = try([for v in try(jsondecode(var.environment_variables_env), var.environment_variables_env) : { name = tostring(v.name), value = tostring(v.value) }], [])

  # Datadog por último: política da plataforma, o app não sobrescreve DD_*/AWS_LAMBDA_EXEC_WRAPPER.
  env_vars = merge(
    { for v in local.env_vars_common : v.name => v.value },
    { for v in local.env_vars_env : v.name => v.value },
    local.datadog_env_vars,
  )

  ########################################
  # Datadog APM (só prd) — layer do tracer do runtime + Datadog-Extension, ativados por
  # AWS_LAMBDA_EXEC_WRAPPER=/opt/datadog_wrapper (o handler declarado não muda).
  # Conta das layers públicas da Datadog: 464622532012. Nome por runtime/arquitetura:
  #   dotnet*  -> dd-trace-dotnet[-ARM]      nodejs20.x -> Datadog-Node20-x[-ARM]
  #   python3.12 -> Datadog-Python312[-ARM]  extension  -> Datadog-Extension[-ARM]
  ########################################

  datadog_enabled        = var.datadog.enabled
  datadog_arch_suffix    = var.lambda.architecture == "arm64" ? "-ARM" : ""
  datadog_runtime_family = try(regex("^(dotnet|nodejs|python)", var.lambda.runtime)[0], "")
  datadog_tracer_layer_name = (
    local.datadog_runtime_family == "nodejs" ? "Datadog-Node${split(".", trimprefix(var.lambda.runtime, "nodejs"))[0]}-x" :
    local.datadog_runtime_family == "python" ? "Datadog-Python${replace(trimprefix(var.lambda.runtime, "python"), ".", "")}" :
    local.datadog_runtime_family == "dotnet" ? "dd-trace-dotnet" : ""
  )
  datadog_layer_arns = local.datadog_enabled ? [
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:${local.datadog_tracer_layer_name}${local.datadog_arch_suffix}:${var.datadog.tracer_layer_version}",
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension${local.datadog_arch_suffix}:${var.datadog.extension_layer_version}",
  ] : []
  datadog_env_vars = local.datadog_enabled ? merge({
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/datadog_wrapper"
    DD_SITE                    = var.datadog.site
    DD_API_KEY_SECRET_ARN      = var.datadog.api_key_secret_arn
    DD_ENV                     = var.environment
    DD_SERVICE                 = var.app_name
    DD_TRACE_ENABLED           = "true"
    DD_SERVERLESS_LOGS_ENABLED = "false" # só trace: sem envio de logs
    DD_ENHANCED_METRICS        = "false" # só trace: sem métricas enhanced
    DD_CAPTURE_LAMBDA_PAYLOAD  = "false"
  }, var.release_version != "" ? { DD_VERSION = var.release_version } : {}) : {}

  lambda_arns  = { for key, mod in module.lambda : key => mod.ARN }
  lambda_names = { for key, mod in module.lambda : key => mod.Name }

  ########################################
  # SQS / SNS — mesma convenção de nome do legado e do backend (lookup externo)
  ########################################

  sqs_name_prefix = "sqs-${var.environment}-${var.aws_region}"
  sns_name_prefix = "sns-${var.environment}-${var.aws_region}"

  sqs_queues = {
    for q in var.resources.sqs : q.queue_name => merge(q, {
      full_name = "${local.sqs_name_prefix}-${q.queue_name}${local.suffix}${q.fifo_queue ? ".fifo" : ""}"
    })
  }

  dlq_queues = {
    for name, q in local.sqs_queues : name => {
      full_name  = "${local.sqs_name_prefix}-${trimspace(q.dlq_queue_name)}${local.suffix}${q.fifo_queue ? ".fifo" : ""}"
      fifo_queue = q.fifo_queue
    } if trimspace(q.dlq_queue_name) != ""
  }

  sns_topics = {
    for t in var.resources.sns_topics : t.topic_name => merge(t, {
      full_name = "${local.sns_name_prefix}-${t.topic_name}${local.suffix}${t.fifo_topic ? ".fifo" : ""}"
    })
  }

  managed_queue_names = toset(keys(local.sqs_queues))
  managed_topic_names = toset(keys(local.sns_topics))

  # Referências a filas/tópicos que não são gerenciados aqui viram lookup por nome (sem sufixo:
  # recurso de outro app, fora do sandbox).
  external_queue_names = toset([
    for name in concat(
      [for t in var.resources.sqs_triggers : t.queue_name],
      [for s in var.resources.sns_sqs_subscriptions : s.queue_name],
      [for p in var.resources.pipes : p.source_queue],
    ) : name if !contains(local.managed_queue_names, name)
  ])
  external_topic_names = toset([
    for s in var.resources.sns_sqs_subscriptions : s.topic_name if !contains(local.managed_topic_names, s.topic_name)
  ])

  queue_arns = merge(
    { for name, q in aws_sqs_queue.this : name => q.arn },
    { for name, d in data.aws_sqs_queue.existing : name => d.arn },
  )
  queue_urls = merge(
    { for name, q in aws_sqs_queue.this : name => q.url },
    { for name, d in data.aws_sqs_queue.existing : name => d.url },
  )
  topic_arns = merge(
    { for name, t in aws_sns_topic.this : name => t.arn },
    { for name, d in data.aws_sns_topic.existing : name => d.arn },
  )

  # Filas gerenciadas que recebem assinatura SNS: precisam de policy liberando SendMessage do tópico.
  subscribed_queues = {
    for name in distinct([for s in var.resources.sns_sqs_subscriptions : s.queue_name]) : name => [
      for s in var.resources.sns_sqs_subscriptions : local.topic_arns[s.topic_name] if s.queue_name == name
    ] if contains(local.managed_queue_names, name)
  }

  ########################################
  # Step Functions / Pipes
  ########################################

  step_functions = {
    for s in var.resources.step_functions : s.name => merge(s, {
      full_name       = "${var.function_name_prefix}-${s.name}${local.suffix}"
      definition_path = "${path.root}/${var.definitions_dir}/${s.definition_file}"
    })
  }

  # Variáveis disponíveis dentro do ASL (templatefile).
  definition_vars = {
    environment     = var.environment
    aws_region      = var.aws_region
    resource_suffix = local.suffix
    lambda_arns     = local.lambda_arns
    lambda_names    = local.lambda_names
    sns_arns        = local.topic_arns
    sqs_arns        = local.queue_arns
    sqs_urls        = local.queue_urls
  }

  pipes = {
    for p in var.resources.pipes : p.name => merge(p, {
      full_name = "${var.function_name_prefix}-${p.name}${local.suffix}"
    })
  }

  ########################################
  # SSM / Secrets — isolamento de sandbox por prefixo de caminho (igual ao backend)
  ########################################

  ssm_params      = try([for p in try(jsondecode(var.ssm_parameters), var.ssm_parameters) : p if can(p.name)], [])
  sdx_path_prefix = local.suffix == "" ? "" : trimprefix(local.suffix, "-")

  ssm_params_named = [
    for p in local.ssm_params : merge(p, {
      effective_name = local.sdx_path_prefix == "" ? p.name : (
        length(regexall("^/(dev|hml|prd)/", p.name)) > 0
        ? replace(p.name, "/^/(dev|hml|prd)//", "/${local.sdx_path_prefix}/")
        : "/${local.sdx_path_prefix}${startswith(p.name, "/") ? "" : "/"}${p.name}"
      )
    })
  ]

  secrets_named = [
    for s in var.resources.secrets : merge(s, {
      effective_name = local.sdx_path_prefix == "" ? s.name : (
        startswith(s.name, "/")
        ? "/${local.sdx_path_prefix}${s.name}"
        : "${local.sdx_path_prefix}/${s.name}"
      )
    })
  ]

  ########################################
  # Policy da role das funções: só os statements com recursos declarados
  ########################################

  lambda_policy_statements = concat(
    length(aws_ssm_parameter.this) == 0 ? [] : [{
      sid       = "SsmParameters"
      actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      resources = [for p in aws_ssm_parameter.this : p.arn]
    }],
    length(aws_secretsmanager_secret.this) == 0 ? [] : [{
      sid       = "Secrets"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [for s in aws_secretsmanager_secret.this : s.arn]
    }],
    length(local.queue_arns) == 0 ? [] : [{
      sid = "Sqs"
      actions = [
        "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ChangeMessageVisibility",
      ]
      resources = concat(values(local.queue_arns), [for d in aws_sqs_queue.dlq : d.arn])
    }],
    length(local.topic_arns) == 0 ? [] : [{
      sid       = "Sns"
      actions   = ["sns:Publish"]
      resources = values(local.topic_arns)
    }],
    # ARN por padrão (conta = *) para não criar ciclo função -> state machine -> definição -> função.
    length(var.resources.step_functions) == 0 ? [] : [{
      sid       = "StepFunctions"
      actions   = ["states:StartExecution", "states:DescribeExecution"]
      resources = ["arn:aws:states:${var.aws_region}:*:stateMachine:${var.function_name_prefix}-*"]
    }],
    # A extension lê a API key do Secrets Manager no cold start. Segredo com CMK exige kms:Decrypt à parte.
    !local.datadog_enabled ? [] : [{
      sid       = "DatadogApiKey"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.datadog.api_key_secret_arn]
    }],
  )
}
