data "aws_region" "current" {}

# Usado para montar o ARN dos log groups na policy da role de execução das
# Lambdas, sem precisar de curinga na conta.
data "aws_caller_identity" "current" {}

data "aws_sns_topic" "existing" {
  for_each = local.external_topic_names
  name     = each.value
}

data "aws_sqs_queue" "existing" {
  for_each = local.external_queue_names
  name     = each.value
}
