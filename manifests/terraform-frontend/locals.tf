locals {
  cloudfront_enabled = lower(tostring(var.cloudfront_enabled)) == "true"
  cf_count           = local.cloudfront_enabled ? 1 : 0
  lookup_cert        = local.cloudfront_enabled && var.acm_certificate_arn == "" ? 1 : 0

  # prd sem sufixo; sandbox (resource_suffix != "") usa o sufixo (default -sdx; custom isola outro
  # sandbox do mesmo app, como no EKS); demais ambientes usam -<env>.
  host_label  = var.environment == "prd" ? var.dns_name : (var.resource_suffix != "" ? "${var.dns_name}${var.resource_suffix}" : "${var.dns_name}-${var.environment}")
  domain_name = "${local.host_label}.${var.base_domain}"

  certificate_arn = local.cloudfront_enabled ? (var.acm_certificate_arn != "" ? var.acm_certificate_arn : data.aws_acm_certificate.this[0].arn) : ""

  # Managed policies do CloudFront (IDs públicos e estáveis da AWS)
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  origin_request_policy_cors_s3  = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin

  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
    Projeto   = var.project_name
    Sistema   = var.sistema
    Owner     = var.owner
  }
}
