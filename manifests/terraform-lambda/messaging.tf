########################################
# SQS (com DLQ opcional) / SNS / assinaturas / triggers SQS -> função
#
# Convenção de nome do legado e do backend (manifests/terraform/locals.tf) — é por ela que um
# app encontra a fila do outro no lookup. Mudou lá, mude aqui.
########################################

locals {
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

  # Gerenciados + externos, por nome lógico: é o que IAM, triggers, ASL e pipes consomem.
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
  # Uma policy por fila, com todos os tópicos (aws_sqs_queue_policy é única por fila).
  subscribed_queues = {
    for name in distinct([for s in var.resources.sns_sqs_subscriptions : s.queue_name]) : name => [
      for s in var.resources.sns_sqs_subscriptions : local.topic_arns[s.topic_name] if s.queue_name == name
    ] if contains(local.managed_queue_names, name)
  }
}

# Lookups só para referências a recursos de OUTROS apps (não gerenciados neste state).
# Em plan offline (terraform test) esses sets ficam vazios e nada é consultado.

data "aws_sqs_queue" "existing" {
  for_each = local.external_queue_names
  name     = "${local.sqs_name_prefix}-${each.value}"
}

data "aws_sns_topic" "existing" {
  for_each = local.external_topic_names
  name     = "${local.sns_name_prefix}-${each.value}"
}

########################################
# Filas e tópicos
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

########################################
# Assinaturas SNS -> SQS (+ policy da fila)
########################################

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
