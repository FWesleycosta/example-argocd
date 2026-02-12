################################################################################
# IAM Role for Step Functions
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "StepFunctionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    # Boa prática: restringir ao account ID para evitar confused deputy
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name               = "${var.name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# Política base para logging (anexada apenas se logging estiver habilitado)
data "aws_iam_policy_document" "logging" {
  count = var.create_log_group ? 1 : 0

  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "logging" {
  count = var.create_log_group ? 1 : 0

  name   = "${var.name}-sfn-logging"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.logging[0].json
}

# Permite anexar políticas adicionais customizadas
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.step_functions.name
  policy_arn = each.value
}
