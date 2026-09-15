locals {
  cloudfront_enabled = lower(tostring(var.cloudfront_enabled)) == "true"
  cf_count           = local.cloudfront_enabled ? 1 : 0
  lookup_cert        = local.cloudfront_enabled && var.acm_certificate_arn == "" ? 1 : 0

  certificate_arn = var.acm_certificate_arn != "" ? var.acm_certificate_arn : try(data.aws_acm_certificate.this[0].arn, "")

  domain_name = var.resource_suffix != "" ? "${var.dns_name}${var.resource_suffix}.${var.base_domain}" : (
    var.environment == "prd" ? "${var.dns_name}.${var.base_domain}" : "${var.dns_name}-${var.environment}.${var.base_domain}"
  )

  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
    Projeto   = var.project_name
    Sistema   = var.sistema
    Owner     = var.owner
  }
}
 
