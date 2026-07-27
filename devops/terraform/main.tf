resource "aws_lambda_function" "this" {

  count = var.create_lambda_function ? 1 : 0

  function_name    = var.function_name
  description      = var.description
  role             = var.role
  memory_size      = var.memory_size
  timeout          = var.timeout
  handler          = var.handler
  tags             = merge(var.tags)
  package_type     = var.package_type
  runtime          = var.runtime
  publish          = var.publish
  filename         = var.filename
  source_code_hash = var.source_code_hash

  layers = concat(
    [for l in data.aws_lambda_layer_version.this : l.arn],
    var.layer_arns,
  )

  environment {
    variables = merge(coalesce(var.environment, {}))
  }

  ephemeral_storage {
    size = var.ephemeral_storage
  }

  vpc_config {
    security_group_ids = var.security_group_ids
    subnet_ids         = var.subnet_ids
  }

  tracing_config {
    mode = var.tracing_config
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
