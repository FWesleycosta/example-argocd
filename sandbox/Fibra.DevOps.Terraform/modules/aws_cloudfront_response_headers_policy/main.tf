resource "aws_cloudfront_response_headers_policy" "this" {
  count = local.create

  name    = var.name
  comment = var.comment

  dynamic "cors_config" {
    for_each = var.cors.enabled ? [1] : []
    content {
      access_control_allow_credentials = var.cors.allow_credentials
      access_control_allow_headers {
        items = var.cors.allow_headers
      }
      access_control_allow_methods {
        items = var.cors.allow_methods
      }
      access_control_allow_origins {
        items = var.cors.allow_origins
      }
      dynamic "access_control_expose_headers" {
        for_each = length(var.cors.expose_headers) > 0 ? [1] : []
        content {
          items = var.cors.expose_headers
        }
      }
      access_control_max_age_sec = var.cors.max_age_sec
      origin_override            = var.cors.origin_override
    }
  }

  dynamic "security_headers_config" {
    for_each = var.security_headers.enabled ? [1] : []
    content {
      strict_transport_security {
        access_control_max_age_sec = var.security_headers.hsts_max_age_sec
        include_subdomains         = var.security_headers.hsts_include_subdomains
        preload                    = var.security_headers.hsts_preload
        override                   = var.security_headers.override
      }
      dynamic "content_type_options" {
        for_each = var.security_headers.content_type_options ? [1] : []
        content {
          override = var.security_headers.override
        }
      }
      dynamic "frame_options" {
        for_each = var.security_headers.frame_option != "" ? [1] : []
        content {
          frame_option = var.security_headers.frame_option
          override     = var.security_headers.override
        }
      }
      dynamic "referrer_policy" {
        for_each = var.security_headers.referrer_policy != "" ? [1] : []
        content {
          referrer_policy = var.security_headers.referrer_policy
          override        = var.security_headers.override
        }
      }
      dynamic "xss_protection" {
        for_each = var.security_headers.xss_protection ? [1] : []
        content {
          mode_block = true
          protection = true
          override   = var.security_headers.override
        }
      }
      dynamic "content_security_policy" {
        for_each = var.security_headers.content_security_policy != "" ? [1] : []
        content {
          content_security_policy = var.security_headers.content_security_policy
          override                = var.security_headers.override
        }
      }
    }
  }

  dynamic "custom_headers_config" {
    for_each = length(var.custom_headers) > 0 ? [1] : []
    content {
      dynamic "items" {
        for_each = var.custom_headers
        content {
          header   = items.value.header
          value    = items.value.value
          override = items.value.override
        }
      }
    }
  }

  dynamic "remove_headers_config" {
    for_each = length(var.remove_headers) > 0 ? [1] : []
    content {
      dynamic "items" {
        for_each = var.remove_headers
        content {
          header = items.value
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.name != null && var.name != ""
      error_message = "name é obrigatório quando create_response_headers_policy = true."
    }
    precondition {
      condition     = var.cors.enabled || var.security_headers.enabled || length(var.custom_headers) > 0 || length(var.remove_headers) > 0
      error_message = "A policy precisa de ao menos um bloco: cors, security_headers, custom_headers ou remove_headers."
    }
  }
}
