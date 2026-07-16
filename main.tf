locals {
  is_public  = var.api_type == "public"  ? 1 : 0
  is_private = var.api_type == "private" ? 1 : 0

  full_domain_name = "${var.domain_internal_name}+${var.domain_name_id}"

  tags = {
    Ambiente        = var.environment
    ManagedBy       = "Terraform"
    Aplicacao       = var.app_name
  }

  sns_topics = {
    for t in var.topic_name : t.topic_name => {
      topic_name = "sns-${var.environment}-${data.aws_region.current.name}-${t.topic_name}${tobool(lower(t.fifo_topic)) ? ".fifo" : ""}"
      fifo_topic = tobool(lower(t.fifo_topic))
      content_based_deduplication = tobool(lower(t.content_based_deduplication))
    }
  }

  sqs_queues = {
    for q in var.queue_name : q.queue_name => {
      queue_name = "sqs-${var.environment}-${data.aws_region.current.name}-${q.queue_name}${tobool(lower(q.fifo_queue)) ? ".fifo" : ""}"
      fifo_queue = tobool(lower(q.fifo_queue))
    }
  }

  managed_topic_names = toset([for t in var.topic_name : t.topic_name])
  managed_queue_names = toset([for q in var.sqs_queues : q.queue_name])

  external_topic_names = toset([
    for s in var.sns_sqs_subscriptions : s.topic_name
    if !contains(local.managed_topic_names, s.topic_name)
  ])

  external_queue_names = toset([
    for s in var.sns_sqs_subscriptions : s.queue_name
    if !contains(local.managed_queue_names, s.queue_name)
  ])

  ssm_params = try(jsondecode(var.ssm_parameters), var.ssm_parameters)
  s3_buckets = try(jsondecode(var.s3_buckets), var.s3_buckets)


}
 
