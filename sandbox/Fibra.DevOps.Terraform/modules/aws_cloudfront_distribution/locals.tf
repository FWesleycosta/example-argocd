locals {
  create = var.create_cloudfront_distribution ? 1 : 0

  comment      = var.comment != "" ? var.comment : (length(var.aliases) > 0 ? var.aliases[0] : (var.name != null ? var.name : ""))
  use_acm_cert = var.acm_certificate_arn != ""

  # 403 (OAC sem ListBucket) e 404 → SPA
  spa_error_codes = var.spa_fallback ? [403, 404] : []

  # Response headers policy — precedência: id explícito > policy compartilhada por nome >
  # criar por distribuição (opt-in) > managed da AWS "CORS-and-SecurityHeadersPolicy".
  create_headers_policy       = var.create_cloudfront_distribution && var.create_response_headers_policy && var.response_headers_policy_id == "" && var.response_headers_policy_name == "" ? 1 : 0
  lookup_headers_policy       = var.create_cloudfront_distribution && var.response_headers_policy_id == "" && var.response_headers_policy_name != "" ? 1 : 0
  managed_cors_and_sec_policy = "e61eb60c-9c35-4d20-a928-2b84e02af89c" # Managed-CORS-and-SecurityHeadersPolicy
  response_headers_policy_id = (
    var.response_headers_policy_id != "" ? var.response_headers_policy_id :
    local.lookup_headers_policy == 1 ? data.aws_cloudfront_response_headers_policy.shared[0].id :
    local.create_headers_policy == 1 ? aws_cloudfront_response_headers_policy.this[0].id :
    local.managed_cors_and_sec_policy
  )
}
