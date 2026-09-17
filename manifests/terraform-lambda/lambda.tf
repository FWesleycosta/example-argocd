########################################
# Funções — um pacote, N handlers
########################################

locals {
  # <prefix>-<handler><suffix>: o sufixo isola o sandbox (o nome não embute o ambiente).
  function_names = {
    for key, _ in var.lambda.handlers : key => "${var.function_name_prefix}-${key}${local.suffix}"
  }

  sg_name = "${var.function_name_prefix}${local.suffix}-lambda"

  subnet_ids  = compact([for s in split(",", var.subnet_ids_csv) : trimspace(s)])
  vpc_enabled = length(local.subnet_ids) > 0

  # Hash só quando o pacote existe no workdir: permite plan/test sem o zip (hash nulo = sem diff de código).
  package_hash = fileexists(var.package_file) ? filebase64sha256(var.package_file) : null

  # "" / null / JSON string / lista -> lista de {name, value} (chave omitida no app chega como "").
  env_vars_common = try([for v in try(jsondecode(var.environment_variables_common), var.environment_variables_common) : { name = tostring(v.name), value = tostring(v.value) }], [])
  env_vars_env    = try([for v in try(jsondecode(var.environment_variables_env), var.environment_variables_env) : { name = tostring(v.name), value = tostring(v.value) }], [])

  # Datadog por último: política da plataforma, o app não sobrescreve DD_*/AWS_LAMBDA_EXEC_WRAPPER.
  env_vars = merge(
    { for v in local.env_vars_common : v.name => v.value },
    { for v in local.env_vars_env : v.name => v.value },
    local.datadog_env_vars,
  )

  lambda_arns  = { for key, mod in module.lambda : key => mod.ARN }
  lambda_names = { for key, mod in module.lambda : key => mod.Name }
}

# Security group (só com VPC) — Lambda não recebe tráfego; só egress.
resource "aws_security_group" "lambda" {
  count       = local.vpc_enabled ? 1 : 0
  name        = local.sg_name
  description = "Lambdas ${var.function_name_prefix}${local.suffix} (egress)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Saida para SSM, filas, APIs e bancos"
  }

  tags = merge(local.tags, { Name = local.sg_name })
}

module "lambda" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_lambda_function"

  for_each = var.lambda.handlers

  function_name    = local.function_names[each.key]
  description      = var.lambda.description != "" ? var.lambda.description : "${var.app_name} (${each.key})"
  role             = aws_iam_role.lambda.arn
  handler          = each.value
  runtime          = var.lambda.runtime
  architectures    = [var.lambda.architecture]
  memory_size      = var.lambda.memory_size
  timeout          = var.lambda.timeout
  tracing_config   = var.lambda.tracing_config
  package_type     = "Zip"
  filename         = var.package_file
  source_code_hash = local.package_hash
  publish          = false

  environment        = length(local.env_vars) > 0 ? local.env_vars : null
  subnet_ids         = local.vpc_enabled ? local.subnet_ids : null
  security_group_ids = local.vpc_enabled ? [aws_security_group.lambda[0].id] : null
  log_retention_days = var.lambda.log_retention_days
  layer_arns         = concat(var.lambda.layer_arns, local.datadog_layer_arns) # Datadog só em prd (local vazio nos demais)

  tags = merge(local.tags, { Funcao = local.function_names[each.key] })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]
}