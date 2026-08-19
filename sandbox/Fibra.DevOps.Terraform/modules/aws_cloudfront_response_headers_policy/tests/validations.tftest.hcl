########################################
# Validations e preconditions.
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

run "frame_option_invalido" {
  command = plan
  variables {
    security_headers = { frame_option = "ALLOW-FROM" }
  }
  expect_failures = [var.security_headers]
}

run "referrer_policy_invalido" {
  command = plan
  variables {
    security_headers = { referrer_policy = "foo" }
  }
  expect_failures = [var.security_headers]
}

run "sem_name" {
  command = plan
  variables { name = "" }
  expect_failures = [aws_cloudfront_response_headers_policy.this]
}

run "sem_nenhum_bloco" {
  command = plan
  variables {
    cors             = { enabled = false }
    security_headers = { enabled = false }
  }
  expect_failures = [aws_cloudfront_response_headers_policy.this]
}
