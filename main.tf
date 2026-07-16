locals {
  is_public  = var.api_type == "public"  ? 1 : 0
  is_private = var.api_type == "private" ? 1 : 0
  full_domain_name = "${var.domain_internal_name}+${var.domain_name_id}"
  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
  }

  sns_topics = {
    for t in var.topic_name : t.topic_name => {
      topic_name                  = "sns-${var.environment}-${data.aws_region.current.name}-${t.topic_name}${tobool(lower(t.fifo_topic)) ? ".fifo" : ""}"
      fifo_topic                  = tobool(lower(t.fifo_topic))
      content_based_deduplication = tobool(lower(t.content_based_deduplication))
    }
  }

  sqs_queues = {
    for q in var.queue_name : q.queue_name => {
      queue_name = "sqs-${var.environment}-${data.aws_region.current.name}-${q.queue_name}${tobool(lower(q.fifo_queue)) ? ".fifo" : ""}"
      fifo_queue = tobool(lower(q.fifo_queue))
    }
  }

  managed_topic_names = toset(keys(local.sns_topics))
  managed_queue_names = toset(keys(local.sqs_queues))

  external_topic_names = toset([
    for s in var.sns_sqs_subscriptions : s.topic_name
    if !contains(local.managed_topic_names, s.topic_name)
  ])
  external_queue_names = toset([
    for s in var.sns_sqs_subscriptions : s.queue_name
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




sns_topic_arn = local.topic_arns[each.value.topic_name]
sqs_queue_arn = local.queue_arns[each.value.queue_name]
sqs_queue_url = local.queue_urls[each.value.queue_name]
