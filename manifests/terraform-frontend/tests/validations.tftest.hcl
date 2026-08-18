########################################
# Validações de variável: entradas inválidas devem falhar no plan.
########################################

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "aws" {
  alias                       = "us_east_1"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  app_name            = "app"
  bucket_name         = "app-dev"
  project_name        = "Proj"
  environment         = "dev"
  aws_region          = "us-east-2"
  dns_name            = "app"
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
}

run "dns_name_invalido" {
  command = plan
  variables {
    dns_name = "Meu_App"
  }
  expect_failures = [var.dns_name]
}

run "dns_name_com_hifen_na_borda" {
  command = plan
  variables {
    dns_name = "-app-"
  }
  expect_failures = [var.dns_name]
}

run "price_class_invalido" {
  command = plan
  variables {
    price_class = "PriceClass_999"
  }
  expect_failures = [var.price_class]
}
