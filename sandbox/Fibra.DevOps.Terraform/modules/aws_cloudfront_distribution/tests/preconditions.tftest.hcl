########################################
# Preconditions de aws_cloudfront_distribution — avaliadas só quando o recurso
# entra no plan (create_cloudfront_distribution = true).
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
  name               = "fibra-ib-dev"
  origin_domain_name = "fibra-ib-dev.s3.us-east-2.amazonaws.com"
}

run "alias_sem_certificado" {
  command = plan
  variables {
    aliases             = ["app.bancofibra.com.br"]
    acm_certificate_arn = ""
  }
  expect_failures = [aws_cloudfront_distribution.this]
}

run "sem_name" {
  command = plan
  variables { name = "" }
  expect_failures = [aws_cloudfront_distribution.this]
}

run "origem_website_endpoint" {
  command = plan
  variables { origin_domain_name = "fibra-ib-dev.s3-website.us-east-2.amazonaws.com" }
  expect_failures = [aws_cloudfront_distribution.this]
}

run "desligado_ignora_obrigatorios" {
  command = plan
  variables {
    create_cloudfront_distribution = false
    name                           = null
    origin_domain_name             = null
  }
  assert {
    condition     = length(aws_cloudfront_distribution.this) == 0
    error_message = "Desligado, os obrigatórios não devem ser exigidos."
  }
}
