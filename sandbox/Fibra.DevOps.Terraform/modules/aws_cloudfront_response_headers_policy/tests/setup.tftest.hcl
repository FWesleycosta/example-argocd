########################################
# Caminho feliz: policy compartilhada com defaults da plataforma. command = plan, offline.
########################################

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name = "fibra-security-headers"
}

run "defaults" {
  command = plan
  assert {
    condition     = aws_cloudfront_response_headers_policy.this[0].name == "fibra-security-headers"
    error_message = "name deve ser aplicado."
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 1 && length(aws_cloudfront_response_headers_policy.this[0].security_headers_config) == 1
    error_message = "Defaults devem gerar cors_config e security_headers_config."
  }
  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this[0].security_headers_config).strict_transport_security).access_control_max_age_sec == 31536000
    error_message = "HSTS default de 1 ano mudou sem atualizar o teste."
  }
  assert {
    condition     = length(one(aws_cloudfront_response_headers_policy.this[0].security_headers_config).content_security_policy) == 0
    error_message = "CSP vazio não deve gerar bloco content_security_policy."
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].custom_headers_config) == 0 && length(aws_cloudfront_response_headers_policy.this[0].remove_headers_config) == 0
    error_message = "Sem custom/remove headers não deve haver blocos extras."
  }
}

run "csp_custom_e_remove" {
  command = plan
  variables {
    security_headers = { content_security_policy = "default-src 'self'" }
    custom_headers   = [{ header = "Permissions-Policy", value = "camera=()" }]
    remove_headers   = ["Server", "X-Powered-By"]
  }
  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this[0].security_headers_config).content_security_policy).content_security_policy == "default-src 'self'"
    error_message = "CSP informado deve ser aplicado."
  }
  assert {
    condition     = length(one(aws_cloudfront_response_headers_policy.this[0].custom_headers_config).items) == 1 && length(one(aws_cloudfront_response_headers_policy.this[0].remove_headers_config).items) == 2
    error_message = "custom_headers/remove_headers devem virar items."
  }
}

run "so_security_sem_cors" {
  command = plan
  variables {
    cors = { enabled = false }
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 0
    error_message = "cors.enabled=false deve omitir cors_config."
  }
}

run "desligado" {
  command = plan
  variables {
    create_response_headers_policy = false
    name                           = null
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0 && output.ID == null && output.Name == null
    error_message = "Desligado não cria nada e outputs são null."
  }
}
