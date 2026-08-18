########################################
# Validações de variável: entradas inválidas devem falhar no plan.
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

run "price_class_invalido" {
  command = plan
  variables { price_class = "PriceClass_999" }
  expect_failures = [var.price_class]
}

run "http_version_invalido" {
  command = plan
  variables { http_version = "http4" }
  expect_failures = [var.http_version]
}

run "frame_option_invalido" {
  command = plan
  variables { frame_option = "ALLOW-FROM" }
  expect_failures = [var.frame_option]
}

run "referrer_policy_invalido" {
  command = plan
  variables { referrer_policy = "foo" }
  expect_failures = [var.referrer_policy]
}

run "geo_restriction_invalido" {
  command = plan
  variables {
    geo_restriction = { restriction_type = "allow" }
  }
  expect_failures = [var.geo_restriction]
}

run "tls_invalido" {
  command = plan
  variables { minimum_protocol_version = "TLSv1.3" }
  expect_failures = [var.minimum_protocol_version]
}
