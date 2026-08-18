terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Provider padrão para us-east-2 (Ohio), onde seu S3 e outros recursos estão
provider "aws" {
  region = var.AWS_REGION
  default_tags {
    tags = {
      environment = "dev"
      terraform   = "true"
      project     = "workloads-dev"
    }
  }
}

# NOVO: Provider específico para us-east-1 (N. Virginia) para o certificado ACM do CloudFront
provider "aws" {
  alias  = "virginia" # Damos um alias para poder referenciá-lo
  region = "us-east-1"
  default_tags {
    tags = {
      environment = "dev"
      terraform   = "true"
      project     = "workloads-dev"
    }
  }
}
 
