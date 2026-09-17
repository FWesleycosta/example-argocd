########################################
# IAM — uma role por app, compartilhada pelas funções (mesmo pacote/código)
# As roles de Step Functions e Pipes ficam em step_functions.tf, junto de quem as usa.
########################################

locals {
  role_name = "lambda-${var.function_name_prefix}${local.suffix}"

  # Policy inline: só os statements com recursos declarados (sem recurso, sem policy).
  lambda_policy_statements = concat(
    length(aws_ssm_parameter.this) == 0 ? [] : [{
      sid       = "SsmParameters"
      actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      resources = [for p in aws_ssm_parameter.this : p.arn]
    }],
    length(aws_secretsmanager_secret.this) == 0 ? [] : [{
      sid       = "Secrets"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [for s in aws_secretsmanager_secret.this : s.arn]
    }],
    length(local.queue_arns) == 0 ? [] : [{
      sid = "Sqs"
      actions = [
        "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ChangeMessageVisibility",
      ]
      resources = concat(values(local.queue_arns), [for d in aws_sqs_queue.dlq : d.arn])
    }],
    length(local.topic_arns) == 0 ? [] : [{
      sid       = "Sns"
      actions   = ["sns:Publish"]
      resources = values(local.topic_arns)
    }],
    # ARN por padrão (conta = *) para não criar ciclo função -> state machine -> definição -> função.
    !local.sfn_enabled ? [] : [{
      sid       = "StepFunctions"
      actions   = ["states:StartExecution", "states:DescribeExecution"]
      resources = ["arn:aws:states:${var.aws_region}:*:stateMachine:${var.function_name_prefix}-*"]
    }],
    # A extension lê a API key do Secrets Manager no cold start. Segredo com CMK exige kms:Decrypt à parte.
    !local.datadog_enabled ? [] : [{
      sid       = "DatadogApiKey"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.datadog.api_key_secret_arn]
    }],
  )
}

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

  # Guardas do root inteiro, não só da role: cruzam mais de uma variável (o que `validation`
  # não alcança antes do Terraform 1.9) e `module` não aceita `lifecycle`. Ficam aqui porque
  # toda função depende da role — falham no plan, antes de qualquer recurso.
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
    precondition {
      condition     = !local.datadog_enabled || local.datadog_tracer_layer_name != ""
      error_message = "Datadog habilitado mas não há layer de tracer para o runtime '${var.lambda.runtime}' (suportados: dotnet*, nodejs*, python*)."
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