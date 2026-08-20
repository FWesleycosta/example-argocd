locals {
  create = var.create_cloudfront_distribution ? 1 : 0

  comment      = var.comment != "" ? var.comment : (length(var.aliases) > 0 ? var.aliases[0] : (var.name != null ? var.name : ""))
  use_acm_cert = var.acm_certificate_arn != ""

  # 403 (OAC sem ListBucket) e 404 → SPA
  spa_error_codes = var.spa_fallback ? [403, 404] : []

  # Response headers policy: policy própria é OPT-IN (consome 1 slot do limite de policies
  # custom da conta, default 20); o default associa a managed da AWS (zero slot) ou a
  # policy externa de response_headers_policy_id ("" = nenhuma).
  create_headers_policy      = var.create_cloudfront_distribution && var.create_response_headers_policy ? 1 : 0
  response_headers_policy_id = var.create_response_headers_policy ? try(aws_cloudfront_response_headers_policy.this[0].id, null) : (var.response_headers_policy_id != "" ? var.response_headers_policy_id : null)
}
