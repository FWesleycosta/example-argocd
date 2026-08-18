locals {
  create = var.create_cloudfront_distribution ? 1 : 0

  comment      = var.comment != "" ? var.comment : (length(var.aliases) > 0 ? var.aliases[0] : (var.name != null ? var.name : ""))
  use_acm_cert = var.acm_certificate_arn != ""

  # 403 (OAC sem ListBucket) e 404 → SPA
  spa_error_codes = var.spa_fallback ? [403, 404] : []
}
