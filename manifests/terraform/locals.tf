locals {
  is_public  = var.api_type == "public"  ? 1 : 0
  is_private = var.api_type == "private" ? 1 : 0
  full_domain_name = "${var.domain_internal_name}+${var.domain_name_id}"
  # Azure DevOps interpola booleanos YAML como "True"/"False"; a comparação precisa ser case-insensitive.
  cognito_enabled = lower(tostring(var.cognito)) == "true"

  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
    Projeto   = var.project_name
    Sistema   = var.sistema
    Owner     = var.owner
  }

  sns_topics = {
    for t in var.topic_name : t.topic_name => {
      topic_name                  = "${t.topic_name}${var.resource_suffix}${tobool(lower(t.fifo_topic)) ? ".fifo" : ""}"
      fifo_topic                  = tobool(lower(t.fifo_topic))
      content_based_deduplication = tobool(lower(t.content_based_deduplication))
    }
  }

  sqs_queues = {
    for q in var.queue_name : q.queue_name => {
      queue_name        = "${q.queue_name}${var.resource_suffix}${tobool(lower(q.fifo_queue)) ? ".fifo" : ""}"
      fifo_queue        = tobool(lower(q.fifo_queue))
      dlq_queue_name    = try(trimspace(q.dlq_queue_name), "")
      max_receive_count = tonumber(q.max_receive_count)
    }
  }

  dlq_queues = {
    for name, q in local.sqs_queues : name => {
      queue_name = "${q.dlq_queue_name}${var.resource_suffix}${q.fifo_queue ? ".fifo" : ""}"
      fifo_queue = q.fifo_queue
    } if q.dlq_queue_name != ""
  }

  sns_name_prefix = "sns-${var.environment}-${data.aws_region.current.name}"
  sqs_name_prefix = "sqs-${var.environment}-${data.aws_region.current.name}"

  subscriptions = [
    for s in var.sns_sqs_subscriptions : merge(s, {
      topic_full_name = "${local.sns_name_prefix}-${s.topic_name}"
      queue_full_name = "${local.sqs_name_prefix}-${s.queue_name}"
    })
  ]

  managed_topic_names = toset(keys(local.sns_topics))
  managed_queue_names = toset(keys(local.sqs_queues))

  external_topic_names = toset([
    for s in local.subscriptions : s.topic_name
    if !contains(local.managed_topic_names, s.topic_name)
  ])
  external_queue_names = toset([
    for s in local.subscriptions : s.queue_name
    if !contains(local.managed_queue_names, s.queue_name)
  ])

  topic_arns = merge(
    { for name, mod in module.aws_sns_topic        : name => mod.topic_arn },
    { for name, d   in data.aws_sns_topic.existing : name => d.arn },
  )
  queue_arns = merge(
    { for name, mod in module.aws_sqs_queue        : name => mod.queue_arn },
    { for name, d   in data.aws_sqs_queue.existing : name => d.arn },
  )
  queue_urls = merge(
    { for name, mod in module.aws_sqs_queue        : name => mod.queue_url },
    { for name, d   in data.aws_sqs_queue.existing : name => d.url },
  )

  ssm_params = try(jsondecode(var.ssm_parameters), var.ssm_parameters)
  s3_buckets = try(jsondecode(var.s3_buckets), var.s3_buckets)
}
 
