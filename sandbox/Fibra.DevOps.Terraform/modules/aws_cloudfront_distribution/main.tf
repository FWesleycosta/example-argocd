resource "aws_cloudfront_origin_access_control" "this" {
  count = local.create

  name                              = "oac-${var.name}"
  description                       = "OAC for ${local.comment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Criada SÓ com create_response_headers_policy = true (quota: 20 policies por conta —
# prefira uma policy compartilhada por nome/ID ou a managed da AWS; ver locals.tf).
resource "aws_cloudfront_response_headers_policy" "this" {
  count = local.create_headers_policy

  name    = "headers-${var.name}"
  comment = "CORS${var.enable_security_headers ? " + security headers" : ""} for ${local.comment}"

  cors_config {
    access_control_allow_credentials = false
    access_control_allow_headers {
      items = var.cors_allowed_headers
    }
    access_control_allow_methods {
      items = var.cors_allowed_methods
    }
    access_control_allow_origins {
      items = var.cors_allowed_origins
    }
    access_control_max_age_sec = var.cors_max_age_sec
    origin_override            = true
  }

  dynamic "security_headers_config" {
    for_each = var.enable_security_headers ? [1] : []
    content {
      strict_transport_security {
        access_control_max_age_sec = var.hsts_max_age_sec
        include_subdomains         = true
        preload                    = false
        override                   = true
      }
      content_type_options {
        override = true
      }
      frame_options {
        frame_option = var.frame_option
        override     = true
      }
      referrer_policy {
        referrer_policy = var.referrer_policy
        override        = true
      }
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  count = local.create

  enabled             = true
  is_ipv6_enabled     = var.is_ipv6_enabled
  comment             = local.comment
  aliases             = var.aliases
  default_root_object = var.default_root_object
  price_class         = var.price_class
  http_version        = var.http_version
  web_acl_id          = var.web_acl_id != "" ? var.web_acl_id : null

  origin {
    domain_name              = var.origin_domain_name
    origin_id                = var.name
    origin_access_control_id = aws_cloudfront_origin_access_control.this[0].id
  }

  default_cache_behavior {
    allowed_methods            = var.allowed_methods
    cached_methods             = var.cached_methods
    target_origin_id           = var.name
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = var.cache_policy_id
    origin_request_policy_id   = var.origin_request_policy_id != "" ? var.origin_request_policy_id : null
    response_headers_policy_id = local.response_headers_policy_id
  }

  dynamic "custom_error_response" {
    for_each = local.spa_error_codes
    content {
      error_code            = custom_error_response.value
      response_code         = 200
      response_page_path    = "/${var.default_root_object}"
      error_caching_min_ttl = var.spa_fallback_error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = var.geo_restriction.locations
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.use_acm_cert ? null : true
    acm_certificate_arn            = local.use_acm_cert ? var.acm_certificate_arn : null
    ssl_support_method             = local.use_acm_cert ? "sni-only" : null
    minimum_protocol_version       = local.use_acm_cert ? var.minimum_protocol_version : "TLSv1"
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.name != null && var.name != ""
      error_message = "name é obrigatório quando create_cloudfront_distribution = true."
    }
    precondition {
      condition     = var.origin_domain_name != null && var.origin_domain_name != ""
      error_message = "origin_domain_name é obrigatório quando create_cloudfront_distribution = true."
    }
    precondition {
      condition     = length(var.aliases) == 0 || local.use_acm_cert
      error_message = "aliases exige acm_certificate_arn (certificado em us-east-1 cobrindo os CNAMEs)."
    }
    precondition {
      condition     = var.origin_domain_name == null || !can(regex("s3-website", var.origin_domain_name))
      error_message = "origin_domain_name não pode ser endpoint de website hosting (s3-website-*): OAC exige o endpoint REST regional do bucket."
    }
  }
}
