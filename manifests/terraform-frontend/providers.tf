# Provider padrão: região do ambiente (var.aws_region — vem de variables/env/<env>.yaml via esteira).
provider "aws" {
  region = var.aws_region
}

# CloudFront exige certificado ACM em us-east-1, independentemente da região do bucket.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
