########################################
# Caminho feliz: bucket + CloudFront com defaults, nomes derivados e outputs.
#
# Todos os runs usam `command = plan` — nada é criado na AWS. Credenciais falsas
# + skip_* mantêm a suíte offline. `acm_certificate_arn` é informado para não
# haver lookup de data source (que exigiria a AWS). Requer Terraform >= 1.6.
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
  app_name              = "fibra-internet-banking"
  bucket_name           = "fibra-internet-banking-dev"
  project_name          = "Fibra.Canais"
  environment           = "dev"
  aws_region            = "us-east-2"
  dns_name              = "internet-banking"
  cloudfront_enabled    = "True" # como o Azure DevOps interpola booleanos
  access_logging_bucket = "access-logging-workloads-dev"
  acm_certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  sistema               = "internet-banking"
  owner                 = "squad-canais"
}

run "dev_com_cloudfront" {
  command = plan

  assert {
    condition     = aws_s3_bucket.site.bucket == "fibra-internet-banking-dev"
    error_message = "O bucket deve receber exatamente var.bucket_name."
  }
  assert {
    condition     = length(module.cloudfront) == 1
    error_message = "cloudfront_enabled='True' (case-insensitive) deve criar a distribuição."
  }
  assert {
    condition     = local.domain_name == "internet-banking-dev.bancofibra.com.br"
    error_message = "Fora de prd o domínio deve embutir o ambiente: <dns>-<env>.<base>."
  }
  assert {
    condition     = output.domain_name == "internet-banking-dev.bancofibra.com.br"
    error_message = "A distribuição deve ter o alias do domínio derivado."
  }
  assert {
    condition     = length(data.aws_acm_certificate.this) == 0
    error_message = "Com acm_certificate_arn informado não deve haver lookup no ACM."
  }
  assert {
    condition     = length(aws_s3_bucket_logging.site) == 1 && aws_s3_bucket_logging.site[0].target_prefix == "s3/fibra-internet-banking-dev/"
    error_message = "access_logging_bucket informado deve habilitar logging com prefixo s3/<bucket>/."
  }
  assert {
    condition     = output.domain_name == "internet-banking-dev.bancofibra.com.br" && output.site_url == "https://internet-banking-dev.bancofibra.com.br"
    error_message = "Outputs domain_name/site_url inconsistentes com o domínio derivado."
  }
  assert {
    condition     = aws_s3_bucket.site.tags["Sistema"] == "internet-banking" && aws_s3_bucket.site.tags["Owner"] == "squad-canais" && aws_s3_bucket.site.tags["Ambiente"] == "dev"
    error_message = "Tags de governança (Sistema/Owner/Ambiente) devem ser aplicadas ao bucket."
  }
}

run "prd_sem_sufixo_de_ambiente" {
  command = plan

  variables {
    environment = "prd"
    bucket_name = "fibra-internet-banking-prd"
  }

  assert {
    condition     = local.domain_name == "internet-banking.bancofibra.com.br"
    error_message = "Em prd o domínio não deve embutir o ambiente."
  }
}

run "sdx_default" {
  command = plan

  variables {
    environment     = "sdx"
    bucket_name     = "fibra-internet-banking-sdx" # a esteira envia <app><suffix>
    resource_suffix = "-sdx"
  }

  assert {
    condition     = local.domain_name == "internet-banking-sdx.bancofibra.com.br"
    error_message = "sdx default: o sufixo -sdx substitui -<env> no domínio (sem duplicar '-sdx-sdx')."
  }
  assert {
    condition     = aws_s3_bucket.site.bucket == "fibra-internet-banking-sdx"
    error_message = "Nomes derivados do bucket devem carregar o sufixo."
  }
}

run "sdx_sufixo_customizado_isola_outro_sandbox" {
  command = plan

  variables {
    environment     = "sdx"
    bucket_name     = "fibra-internet-banking-wesley"
    resource_suffix = "-wesley"
  }

  assert {
    condition     = local.domain_name == "internet-banking-wesley.bancofibra.com.br"
    error_message = "Sufixo customizado deve gerar domínio próprio (mesma semântica do resourceSuffix no EKS)."
  }
  assert {
    condition     = aws_s3_bucket.site.bucket == "fibra-internet-banking-wesley" && output.domain_name == "internet-banking-wesley.bancofibra.com.br"
    error_message = "Bucket e domínio devem ser isolados pelo sufixo customizado."
  }
}

run "dev_sem_sufixo_usa_env" {
  command = plan

  variables {
    resource_suffix = ""
  }

  assert {
    condition     = local.domain_name == "internet-banking-dev.bancofibra.com.br"
    error_message = "Sem sufixo, o domínio usa -<env>."
  }
}

run "sem_cloudfront" {
  command = plan

  variables {
    cloudfront_enabled    = "false"
    access_logging_bucket = ""
  }

  assert {
    condition     = length(module.cloudfront) == 0
    error_message = "cloudfront_enabled=false não deve criar recursos de CloudFront."
  }
  assert {
    condition     = length(data.aws_acm_certificate.this) == 0
    error_message = "Sem CloudFront não há lookup de certificado."
  }
  assert {
    condition     = length(aws_s3_bucket_logging.site) == 0
    error_message = "access_logging_bucket vazio não deve configurar logging."
  }
  assert {
    condition     = output.cloudfront_distribution_id == "" && output.site_url == ""
    error_message = "Sem CloudFront os outputs de distribuição/URL devem ser vazios (o motor trata vazio como 'não invalidar')."
  }
}
