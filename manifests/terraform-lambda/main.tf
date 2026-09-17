########################################
# IAM — uma role por app, compartilhada pelas funções (mesmo pacote/código)
########################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags

  lifecycle {
    precondition {
      condition     = length(local.role_name) <= 64
      error_message = "Nome da role '${local.role_name}' excede 64 caracteres. Informe lambda.function_name_prefix mais curto."
    }
    precondition {
      condition     = alltrue([for n in values(local.function_names) : length(n) <= 64])
      error_message = "Nome de função acima de 64 caracteres: ${join(", ", [for n in values(local.function_names) : n if length(n) > 64])}. Encurte lambda.function_name_prefix ou a chave do handler."
    }
    precondition {
      condition     = !local.vpc_enabled || var.vpc_id != ""
      error_message = "subnet_ids_csv informado sem vpc_id (variables/env/<env>.yaml: vpcId)."
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = local.vpc_enabled ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.lambda.tracing_config == "Active" ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "lambda_permissions" {
  count = length(local.lambda_policy_statements) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = local.lambda_policy_statements
    content {
      sid       = statement.value.sid
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  count  = length(local.lambda_policy_statements) > 0 ? 1 : 0
  name   = "app-resources"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions[0].json
}

########################################
# Security group (só com VPC) — Lambda não recebe tráfego; só egress
########################################

resource "aws_security_group" "lambda" {
  count       = local.vpc_enabled ? 1 : 0
  name        = local.sg_name
  description = "Lambdas ${var.function_name_prefix}${local.suffix} (egress)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Saida para SSM, filas, APIs e bancos"
  }

  tags = merge(local.tags, { Name = local.sg_name })
}

########################################
# Funções — um pacote, N handlers
########################################

module "lambda" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_lambda_function"

  for_each = var.lambda.handlers

  function_name    = local.function_names[each.key]
  description      = var.lambda.description != "" ? var.lambda.description : "${var.app_name} (${each.key})"
  role             = aws_iam_role.lambda.arn
  handler          = each.value
  runtime          = var.lambda.runtime
  architectures    = [var.lambda.architecture]
  memory_size      = var.lambda.memory_size
  timeout          = var.lambda.timeout
  tracing_config   = var.lambda.tracing_config
  package_type     = "Zip"
  filename         = var.package_file
  source_code_hash = local.package_hash
  publish          = false

  environment        = length(local.env_vars) > 0 ? local.env_vars : null
  subnet_ids         = local.vpc_enabled ? local.subnet_ids : null
  security_group_ids = local.vpc_enabled ? [aws_security_group.lambda[0].id] : null
  log_retention_days = var.lambda.log_retention_days
  layer_arns         = var.lambda.layer_arns

  tags = merge(local.tags, { Funcao = local.function_names[each.key] })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]
}

########################################
# SSM Parameters / Secrets
########################################

resource "aws_ssm_parameter" "this" {
  for_each = { for p in local.ssm_params_named : p.name => p }

  name        = each.value.effective_name
  description = try(each.value.description, "")
  type        = try(each.value.type, "String")
  value       = each.value.value
  tags        = local.tags
}

resource "aws_secretsmanager_secret" "this" {
  for_each = { for s in local.secrets_named : s.name => s }

  name                    = each.value.effective_name
  description             = each.value.description
  recovery_window_in_days = 7
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = jsonencode({ for key in local.secrets_named[index(local.secrets_named.*.name, each.key)].keys : key => "PREENCHER" })

  lifecycle {
    # O valor real é preenchido fora da esteira; nunca sobrescrever.
    ignore_changes = [secret_string]
  }
}

########################################
# SQS (com DLQ opcional) / SNS / assinaturas
########################################

resource "aws_sqs_queue" "dlq" {
  for_each = local.dlq_queues

  name                        = each.value.full_name
  fifo_queue                  = each.value.fifo_queue
  content_based_deduplication = each.value.fifo_queue ? true : null
  message_retention_seconds   = 1209600 # 14 dias para análise/reprocessamento
  receive_wait_time_seconds   = 20
  tags                        = local.tags
}

resource "aws_sqs_queue" "this" {
  for_each = local.sqs_queues

  name                        = each.value.full_name
  fifo_queue                  = each.value.fifo_queue
  content_based_deduplication = each.value.fifo_queue ? true : null
  visibility_timeout_seconds  = each.value.visibility_timeout_seconds
  message_retention_seconds   = each.value.message_retention_seconds
  receive_wait_time_seconds   = each.value.receive_wait_time_seconds

  redrive_policy = contains(keys(local.dlq_queues), each.key) ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  }) : null

  tags = local.tags
}

resource "aws_sns_topic" "this" {
  for_each = local.sns_topics

  name                        = each.value.full_name
  fifo_topic                  = each.value.fifo_topic
  content_based_deduplication = each.value.fifo_topic ? each.value.content_based_deduplication : null
  tags                        = local.tags
}

resource "aws_sns_topic_subscription" "sqs" {
  for_each = { for s in var.resources.sns_sqs_subscriptions : "${s.topic_name}-${s.queue_name}" => s }

  topic_arn            = local.topic_arns[each.value.topic_name]
  protocol             = "sqs"
  endpoint             = local.queue_arns[each.value.queue_name]
  raw_message_delivery = true
  filter_policy        = each.value.filter_policy == null ? null : jsonencode(each.value.filter_policy)
  filter_policy_scope  = each.value.filter_policy == null ? null : each.value.filter_policy_scope

  lifecycle {
    precondition {
      condition     = contains(local.managed_queue_names, each.value.queue_name)
      error_message = "sns_sqs_subscriptions: a fila '${each.value.queue_name}' precisa estar em resources.sqs (a policy da fila é gerenciada aqui)."
    }
  }
}

data "aws_iam_policy_document" "queue_from_sns" {
  for_each = local.subscribed_queues

  statement {
    sid       = "AllowSnsSendMessage"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = each.value
    }
  }
}

resource "aws_sqs_queue_policy" "from_sns" {
  for_each = local.subscribed_queues

  queue_url = aws_sqs_queue.this[each.key].url
  policy    = data.aws_iam_policy_document.queue_from_sns[each.key].json
}

########################################
# Triggers SQS -> função
########################################

resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = { for t in var.resources.sqs_triggers : "${t.handler}-${t.queue_name}" => t }

  event_source_arn                   = local.queue_arns[each.value.queue_name]
  function_name                      = local.lambda_arns[each.value.handler]
  batch_size                         = each.value.batch_size
  maximum_batching_window_in_seconds = each.value.maximum_batching_window_in_seconds
  enabled                            = each.value.enabled
  function_response_types            = each.value.report_batch_item_failures ? ["ReportBatchItemFailures"] : null

  lifecycle {
    precondition {
      condition     = contains(keys(var.lambda.handlers), each.value.handler)
      error_message = "sqs_triggers: handler '${each.value.handler}' não existe em lambda.handlers."
    }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

########################################
# Step Functions
########################################

data "aws_iam_policy_document" "sfn_assume" {
  count = length(var.resources.step_functions) > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sfn_permissions" {
  count = length(var.resources.step_functions) > 0 ? 1 : 0

  statement {
    sid       = "InvokeAppFunctions"
    actions   = ["lambda:InvokeFunction"]
    resources = concat(values(local.lambda_arns), [for a in values(local.lambda_arns) : "${a}:*"])
  }

  dynamic "statement" {
    for_each = length(local.topic_arns) > 0 ? [1] : []
    content {
      sid       = "PublishTopics"
      actions   = ["sns:Publish"]
      resources = values(local.topic_arns)
    }
  }

  dynamic "statement" {
    for_each = length(local.queue_arns) > 0 ? [1] : []
    content {
      sid       = "SendQueues"
      actions   = ["sqs:SendMessage"]
      resources = values(local.queue_arns)
    }
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "sfn" {
  count              = length(var.resources.step_functions) > 0 ? 1 : 0
  name               = "sfn-${var.function_name_prefix}${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "sfn" {
  count  = length(var.resources.step_functions) > 0 ? 1 : 0
  name   = "app-resources"
  role   = aws_iam_role.sfn[0].id
  policy = data.aws_iam_policy_document.sfn_permissions[0].json
}

resource "aws_sfn_state_machine" "this" {
  for_each = local.step_functions

  name       = each.value.full_name
  role_arn   = aws_iam_role.sfn[0].arn
  type       = each.value.type
  definition = templatefile(each.value.definition_path, local.definition_vars)
  tags       = local.tags

  lifecycle {
    precondition {
      condition     = fileexists(each.value.definition_path)
      error_message = "step_functions '${each.key}': definição '${each.value.definition_file}' não encontrada em ${var.definitions_dir}/. No app ela fica em infra/<arquivo>.asl.json."
    }
  }

  depends_on = [aws_iam_role_policy.sfn]
}

########################################
# EventBridge Pipes — SQS -> Step Function
########################################

data "aws_iam_policy_document" "pipes_assume" {
  count = length(var.resources.pipes) > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pipes_permissions" {
  count = length(var.resources.pipes) > 0 ? 1 : 0

  statement {
    sid       = "ReadSourceQueues"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [for p in local.pipes : local.queue_arns[p.source_queue]]
  }

  statement {
    sid       = "StartTargetStateMachines"
    actions   = ["states:StartExecution"]
    resources = [for p in local.pipes : aws_sfn_state_machine.this[p.target_step_function].arn]
  }
}

resource "aws_iam_role" "pipes" {
  count              = length(var.resources.pipes) > 0 ? 1 : 0
  name               = "pipes-${var.function_name_prefix}${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "pipes" {
  count  = length(var.resources.pipes) > 0 ? 1 : 0
  name   = "app-resources"
  role   = aws_iam_role.pipes[0].id
  policy = data.aws_iam_policy_document.pipes_permissions[0].json
}

resource "aws_pipes_pipe" "this" {
  for_each = local.pipes

  name     = each.value.full_name
  role_arn = aws_iam_role.pipes[0].arn
  source   = local.queue_arns[each.value.source_queue]
  target   = aws_sfn_state_machine.this[each.value.target_step_function].arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = each.value.batch_size
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = each.value.invocation_type
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = contains(local.managed_queue_names, each.value.source_queue)
      error_message = "pipes '${each.key}': source_queue '${each.value.source_queue}' precisa estar em resources.sqs."
    }
    precondition {
      condition     = contains(keys(local.step_functions), each.value.target_step_function)
      error_message = "pipes '${each.key}': target_step_function '${each.value.target_step_function}' precisa estar em resources.step_functions."
    }
  }

  depends_on = [aws_iam_role_policy.pipes]
}
