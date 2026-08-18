resource "aws_lambda_function" "this" {

  count = var.create_lambda_function ? 1 : 0

  function_name    = var.function_name
  description      = var.description
  architectures    = var.architectures
  role             = var.role
  memory_size      = var.memory_size
  timeout          = var.timeout
  handler          = var.handler
  tags             = local.tags
  package_type     = var.package_type
  runtime          = var.runtime
  publish          = var.publish
  filename         = var.filename
  source_code_hash = var.source_code_hash
  image_uri        = var.image_uri
  layers           = length(local.all_layers) > 0 ? local.all_layers : null

  dynamic "environment" {
    for_each = nonsensitive(length(local.env_vars) > 0) ? [1] : []
    content {
      variables = local.env_vars
    }
  }

  ephemeral_storage {
    size = var.ephemeral_storage
  }

  dynamic "vpc_config" {
    for_each = local.vpc_enabled ? [1] : []
    content {
      security_group_ids = var.security_group_ids
      subnet_ids         = var.subnet_ids
    }
  }

  tracing_config {
    mode = var.tracing_config
  }

  lifecycle {
    precondition {
      condition     = !local.vpc_enabled || (length(coalesce(var.subnet_ids, [])) > 0 && length(coalesce(var.security_group_ids, [])) > 0)
      error_message = "Para rodar a Lambda na VPC informe subnet_ids E security_group_ids — a AWS exige os dois."
    }

    precondition {
      condition     = length(local.all_layers) <= 5
      error_message = "A AWS permite no máximo 5 layers por função. Você passou ${length(local.all_layers)} (layers + layer_arns)."
    }

    precondition {
      condition     = var.function_name != null
      error_message = "function_name não pode ser nulo. A AWS exige um nome para a função Lambda."
    }

    precondition {
      condition     = var.role != null
      error_message = "role não pode ser nulo. A AWS exige uma role para a função Lambda."
    }

    precondition {
      condition = var.package_type != "Zip" || (
        var.runtime != null && var.handler != null && var.filename != null
      )
      error_message = "Para package_type = \"Zip\", runtime, handler e filename não podem ser nulos."
    }

    precondition {
      condition     = var.package_type != "Image" || var.image_uri != null
      error_message = "Para package_type = \"Image\", image_uri é obrigatório."
    }

    precondition {
      condition = var.package_type != "Image" || (
        var.runtime == null && var.handler == null && var.filename == null
      )
      error_message = "Com package_type = \"Image\", runtime/handler/filename devem ficar nulos — a AWS rejeita a combinação."
    }

    precondition {
      condition     = var.package_type != "Zip" || var.image_uri == null
      error_message = "image_uri só se aplica a package_type = \"Image\". Com \"Zip\", use filename + source_code_hash."
    }
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_lambda_runtime_management_config" "this" {
  count = local.manage_runtime_config ? 1 : 0

  function_name     = aws_lambda_function.this[0].function_name
  update_runtime_on = var.update_runtime_on
}

resource "aws_cloudwatch_log_group" "this" {
  count = var.create_lambda_function ? 1 : 0

  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.function_name != null
      error_message = "function_name não pode ser nulo. A AWS exige um nome para a função Lambda."
    }
  }
}