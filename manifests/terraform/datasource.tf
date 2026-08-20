data "aws_region" "current" {}

data "aws_sns_topic" "existing" {
  for_each = local.external_topic_names
  name     = "${local.sns_name_prefix}-${each.value}"
}

data "aws_sqs_queue" "existing" {
  for_each = local.external_queue_names
  name     = "${local.sqs_name_prefix}-${each.value}"
}

