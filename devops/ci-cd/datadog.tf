locals {

  dd_site                   = "datadoghq.com"

  dd_extension_layer_ver    = 97

  dd_trace_layer_ver        = 23

  dd_api_key_secret_name    = "datadog/api-key"
  dd_profiler_path          = "/var/task/datadog/linux-x64/Datadog.Trace.ClrProfiler.Native.so"
  dd_capture_lambda_payload = "true"
  effective_stage = lower(trimspace(coalesce(var.datadog_env, try(var.tags["Environment"], null), "unset")))

  datadog_enabled = contains(
    [for s in var.datadog_instrumentation_stages : lower(trimspace(s))],
    local.effective_stage,
  )

  datadog_layers = local.datadog_enabled ? [
    "arn:aws:lambda:${data.aws_region.current.name}:464622532012:layer:Datadog-Extension:${local.dd_extension_layer_ver}",
    "arn:aws:lambda:${data.aws_region.current.name}:464622532012:layer:dd-trace-dotnet:${local.dd_trace_layer_ver}",
  ] : []

  datadog_env = local.datadog_enabled ? {

    AWS_LAMBDA_EXEC_WRAPPER = "/opt/datadog_wrapper"

    CORECLR_ENABLE_PROFILING = "1"

    CORECLR_PROFILER           = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
    DD_ENHANCED_METRICS         = "false"
    DD_LOGS_ENABLED             = "false"
    DD_SERVERLESS_LOGS_ENABLED = "false"
    DD_TRACE_ENABLED            = "true"
    DD_SITE                     = local.dd_site
    DD_ENV                      = local.effective_stage
    DD_SERVICE                  = var.function_name
    DD_VERSION                  = var.service_version
    DD_CAPTURE_LAMBDA_PAYLOAD   = local.dd_capture_lambda_payload
    DD_API_KEY_SECRET_ARN       = data.aws_secretsmanager_secret.datadog_api_key[0].arn

  } : {}

}


 
