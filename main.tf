resource "aws_api_gateway_domain_name" "this" {
  domain_name     = var.domain_name
  security_policy = var.security_policy

  endpoint_access_mode = local.needs_endpoint_access_mode ? var.endpoint_access_mode : null

  regional_certificate_arn = local.is_regional ? local.certificate_arn : null
  certificate_arn          = local.is_regional ? null : local.certificate_arn

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  # dynamic "mutual_tls_authentication" {
  #   for_each = var.mutual_tls_truststore_uri != null ? [1] : []
  #   content {
  #     truststore_uri     = var.mutual_tls_truststore_uri
  #     truststore_version = var.mutual_tls_truststore_version
  #   }
  # }

  tags = var.tags
}


variable "domain_name" {
  description = "Custom domain name (e.g.: api.example.com)."
  type        = string
}

variable "endpoint_type" {
  description = "Domain endpoint type: REGIONAL (recommended) or EDGE."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "EDGE"], var.endpoint_type)
    error_message = "endpoint_type must be 'REGIONAL' or 'EDGE'."
  }
}

variable "security_policy" {
  description = "Minimum TLS security policy for the domain. Use a TLS_1_2 (or newer) policy for production workloads; TLS_1_0 is deprecated and should only be used for legacy clients that cannot be upgraded. Note that the available policies differ by endpoint_type: REGIONAL domains support the SecurityPolicy_TLS13_* / SecurityPolicy_TLS12_* values, while EDGE domains support the *_EDGE values and the legacy TLS_1_0 / TLS_1_2 aliases."
  type        = string
  default     = "SecurityPolicy_TLS13_1_3_2025_09"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_2", "SecurityPolicy_TLS13_1_3_2025_09", "SecurityPolicy_TLS13_1_3_FIPS_2025_09", "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_PQ_2025_09", "SecurityPolicy_TLS13_1_2_2021_06", "SecurityPolicy_TLS13_2025_EDGE", "SecurityPolicy_TLS12_PFS_2025_EDGE", "SecurityPolicy_TLS12_2018_EDGE"], var.security_policy)
    error_message = "security_policy must be one of the supported values: TLS_1_0, TLS_1_2, SecurityPolicy_TLS13_1_3_2025_09, SecurityPolicy_TLS13_1_3_FIPS_2025_09, SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09, SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09, SecurityPolicy_TLS13_1_2_PQ_2025_09, SecurityPolicy_TLS13_1_2_2021_06, SecurityPolicy_TLS13_2025_EDGE, SecurityPolicy_TLS12_PFS_2025_EDGE, or SecurityPolicy_TLS12_2018_EDGE."
  }
}

variable "endpoint_access_mode" {
  description = "Endpoint access mode for the custom domain (BASIC or STRICT). Required by the newer SecurityPolicy_TLS13_*/SecurityPolicy_TLS12_* security policies; ignored for the legacy TLS_1_0/TLS_1_2 policies. BASIC keeps the standard behavior; STRICT enforces stricter TLS handling."
  type        = string
  default     = "STRICT"

  validation {
    condition     = contains(["BASIC", "STRICT"], var.endpoint_access_mode)
    error_message = "endpoint_access_mode must be 'BASIC' or 'STRICT'."
  }
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate to use for the custom domain. Leave null to auto-generate a self-signed certificate (see create_test_certificate). For production, point this to a public ACM certificate that you control."
  type        = string
  default     = null
}

variable "certificate_domain" {
  description = "Domain used to look up an existing ACM certificate when certificate_arn is null and create_test_certificate is false. Defaults to domain_name. Set this to a wildcard (e.g.: *.example.com) when the certificate covers subdomains."
  type        = string
  default     = null
}
