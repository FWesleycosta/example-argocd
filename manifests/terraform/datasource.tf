data "aws_sns_topic" "existing" {
  for_each = local.external_topic_names
  name     = each.value
}

data "aws_sqs_queue" "existing" {
  for_each = local.external_queue_names
  name     = each.value
}
