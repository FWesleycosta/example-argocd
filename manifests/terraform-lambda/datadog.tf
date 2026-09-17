########################################
# Datadog APM (só prd) — layer do tracer do runtime + Datadog-Extension, ativados por
# AWS_LAMBDA_EXEC_WRAPPER=/opt/datadog_wrapper (o handler declarado não muda).
# Conta das layers públicas da Datadog: 464622532012. Nome por runtime/arquitetura:
#   dotnet*  -> dd-trace-dotnet[-ARM]      nodejs20.x -> Datadog-Node20-x[-ARM]
#   python3.12 -> Datadog-Python312[-ARM]  extension  -> Datadog-Extension[-ARM]
#
# Só locals: as layers e as DD_* entram na função em lambda.tf; a permissão de leitura da
# API key, na policy de iam.tf.
########################################

locals {
  datadog_enabled        = var.datadog.enabled
  datadog_arch_suffix    = var.lambda.architecture == "arm64" ? "-ARM" : ""
  datadog_runtime_family = try(regex("^(dotnet|nodejs|python)", var.lambda.runtime)[0], "")
  datadog_tracer_layer_name = (
    local.datadog_runtime_family == "nodejs" ? "Datadog-Node${split(".", trimprefix(var.lambda.runtime, "nodejs"))[0]}-x" :
    local.datadog_runtime_family == "python" ? "Datadog-Python${replace(trimprefix(var.lambda.runtime, "python"), ".", "")}" :
    local.datadog_runtime_family == "dotnet" ? "dd-trace-dotnet" : ""
  )
  datadog_layer_arns = local.datadog_enabled ? [
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:${local.datadog_tracer_layer_name}${local.datadog_arch_suffix}:${var.datadog.tracer_layer_version}",
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension${local.datadog_arch_suffix}:${var.datadog.extension_layer_version}",
  ] : []
  datadog_env_vars = local.datadog_enabled ? merge({
    AWS_LAMBDA_EXEC_WRAPPER    = "/opt/datadog_wrapper"
    DD_SITE                    = var.datadog.site
    DD_API_KEY_SECRET_ARN      = var.datadog.api_key_secret_arn
    DD_ENV                     = var.environment
    DD_SERVICE                 = var.app_name
    DD_TRACE_ENABLED           = "true"
    DD_SERVERLESS_LOGS_ENABLED = "false" # só trace: sem envio de logs
    DD_ENHANCED_METRICS        = "false" # só trace: sem métricas enhanced
    DD_CAPTURE_LAMBDA_PAYLOAD  = "false"
  }, var.release_version != "" ? { DD_VERSION = var.release_version } : {}) : {}
}