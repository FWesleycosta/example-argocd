########################################
# Step Functions e EventBridge Pipes (SQS -> Step Function), cada um com sua role
########################################

locals {
  sfn_enabled   = length(var.resources.step_functions) > 0
  pipes_enabled = length(var.resources.pipes) > 0

  step_functions = {
    for s in var.resources.step_functions : s.name => merge(s, {
      full_name       = "${var.function_name_prefix}-${s.name}${local.suffix}"
      definition_path = "${path.root}/${var.definitions_dir}/${s.definition_file}"
    })
  }

  # Variáveis disponíveis dentro do ASL (templatefile) — contrato tabelado no README.
  definition_vars = {
    environment     = var.environment
    aws_region      = var.aws_region
    resource_suffix = local.suffix
    lambda_arns     = local.lambda_arns
    lambda_names    = local.lambda_names
    sns_arns        = local.topic_arns
    sqs_arns        = local.queue_arns
    sqs_urls        = local.queue_urls
  }

  pipes = {
    for p in var.resources.pipes : p.name => merge(p, {
      full_name = "${var.function_name_prefix}-${p.name}${local.suffix}"
    })
  }
}

########################################
# Step Functions
########################################

data "aws_iam_policy_document" "sfn_assume" {
  count = local.sfn_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sfn_permissions" {
  count = local.sfn_enabled ? 1 : 0

  statement {
    sid       = "InvokeAppFunctions"
    actions   = ["lambda:InvokeFunction"]
    resources = concat(values(local.lambda_arns), [for a in values(local.lambda_arns) : "${a}:*"])
  }

  dynamic "statement" {
    for_each = length(local.topic_arns) > 0 ? [1] : []
    content {
      sid       = "PublishTopics"
      actions   = ["sns:Publish"]
      resources = values(local.topic_arns)
    }
  }

  dynamic "statement" {
    for_each = length(local.queue_arns) > 0 ? [1] : []
    content {
      sid       = "SendQueues"
      actions   = ["sqs:SendMessage"]
      resources = values(local.queue_arns)
    }
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "sfn" {
  count              = local.sfn_enabled ? 1 : 0
  name               = "sfn-${var.function_name_prefix}${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "sfn" {
  count  = local.sfn_enabled ? 1 : 0
  name   = "app-resources"
  role   = aws_iam_role.sfn[0].id
  policy = data.aws_iam_policy_document.sfn_permissions[0].json
}

resource "aws_sfn_state_machine" "this" {
  for_each = local.step_functions

  name       = each.value.full_name
  role_arn   = aws_iam_role.sfn[0].arn
  type       = each.value.type
  definition = templatefile(each.value.definition_path, local.definition_vars)
  tags       = local.tags

  lifecycle {
    precondition {
      condition     = fileexists(each.value.definition_path)
      error_message = "step_functions '${each.key}': definição '${each.value.definition_file}' não encontrada em ${var.definitions_dir}/. No app ela fica em infra/<arquivo>.asl.json."
    }
  }

  depends_on = [aws_iam_role_policy.sfn]
}

########################################
# EventBridge Pipes — SQS -> Step Function
########################################

data "aws_iam_policy_document" "pipes_assume" {
  count = local.pipes_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pipes_permissions" {
  count = local.pipes_enabled ? 1 : 0

  statement {
    sid       = "ReadSourceQueues"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [for p in local.pipes : local.queue_arns[p.source_queue]]
  }

  statement {
    sid       = "StartTargetStateMachines"
    actions   = ["states:StartExecution"]
    resources = [for p in local.pipes : aws_sfn_state_machine.this[p.target_step_function].arn]
  }
}

resource "aws_iam_role" "pipes" {
  count              = local.pipes_enabled ? 1 : 0
  name               = "pipes-${var.function_name_prefix}${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.pipes_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "pipes" {
  count  = local.pipes_enabled ? 1 : 0
  name   = "app-resources"
  role   = aws_iam_role.pipes[0].id
  policy = data.aws_iam_policy_document.pipes_permissions[0].json
}

resource "aws_pipes_pipe" "this" {
  for_each = local.pipes

  name     = each.value.full_name
  role_arn = aws_iam_role.pipes[0].arn
  source   = local.queue_arns[each.value.source_queue]
  target   = aws_sfn_state_machine.this[each.value.target_step_function].arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = each.value.batch_size
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = each.value.invocation_type
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = contains(local.managed_queue_names, each.value.source_queue)
      error_message = "pipes '${each.key}': source_queue '${each.value.source_queue}' precisa estar em resources.sqs."
    }
    precondition {
      condition     = contains(keys(local.step_functions), each.value.target_step_function)
      error_message = "pipes '${each.key}': target_step_function '${each.value.target_step_function}' precisa estar em resources.step_functions."
    }
  }

  depends_on = [aws_iam_role_policy.pipes]
}
