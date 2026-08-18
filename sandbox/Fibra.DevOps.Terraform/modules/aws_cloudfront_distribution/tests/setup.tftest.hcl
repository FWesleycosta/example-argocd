########################################
# Caminho feliz: distribuição S3+OAC com defaults, nomes derivados e outputs.
#
# Todos os runs usam `command = plan` — nada é criado na AWS. Credenciais falsas
# + skip_* mantêm a suíte offline. Requer Terraform >= 1.6.
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
  name                = "fibra-ib-dev"
  origin_domain_name  = "fibra-ib-dev.s3.us-east-2.amazonaws.com"
  aliases             = ["internet-banking-dev.bancofibra.com.br"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  tags                = { Ambiente = "dev" }
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.this[0].name == "oac-fibra-ib-dev" && aws_cloudfront_response_headers_policy.this[0].name == "headers-fibra-ib-dev"
    error_message = "OAC e headers policy devem derivar de name."
  }
  assert {
    condition     = aws_cloudfront_distribution.this[0].comment == "internet-banking-dev.bancofibra.com.br"
    error_message = "comment vazio deve cair no primeiro alias."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this[0].custom_error_response) == 2
    error_message = "spa_fallback default deve reescrever 403 e 404."
  }
  assert {
    condition     = aws_cloudfront_distribution.this[0].price_class == "PriceClass_All" && aws_cloudfront_distribution.this[0].http_version == "http2and3"
    error_message = "Defaults de price_class/http_version mudaram sem atualizar o teste."
  }
  assert {
    condition     = one(aws_cloudfront_distribution.this[0].viewer_certificate).minimum_protocol_version == "TLSv1.2_2021" && one(aws_cloudfront_distribution.this[0].viewer_certificate).ssl_support_method == "sni-only"
    error_message = "Com ACM o viewer_certificate deve ser sni-only + TLSv1.2_2021."
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config) == 1
    error_message = "enable_security_headers default deve incluir security_headers_config."
  }
  assert {
    condition     = one(aws_cloudfront_distribution.this[0].default_cache_behavior).cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "Default de cache_policy_id deve ser a managed CachingOptimized."
  }
}

run "sem_security_headers_e_sem_spa" {
  command = plan
  variables {
    enable_security_headers = false
    spa_fallback            = false
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config) == 0
    error_message = "enable_security_headers=false não deve gerar security_headers_config."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this[0].custom_error_response) == 0
    error_message = "spa_fallback=false não deve gerar custom_error_response."
  }
}

run "sem_alias_usa_certificado_padrao" {
  command = plan
  variables {
    aliases             = []
    acm_certificate_arn = ""
    comment             = ""
  }
  assert {
    condition     = one(aws_cloudfront_distribution.this[0].viewer_certificate).cloudfront_default_certificate == true
    error_message = "Sem ACM deve usar o certificado padrão do CloudFront."
  }
  assert {
    condition     = aws_cloudfront_distribution.this[0].comment == "fibra-ib-dev"
    error_message = "Sem alias e sem comment, o comment cai em name."
  }
}

run "desligado" {
  command = plan
  variables {
    create_cloudfront_distribution = false
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this) == 0 && length(aws_cloudfront_origin_access_control.this) == 0 && length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "create_cloudfront_distribution=false não deve criar nada."
  }
  assert {
    condition     = output.ID == null && output.ARN == null && output.Domain_Name == null
    error_message = "Com o módulo desligado os outputs devem ser null."
  }
}
