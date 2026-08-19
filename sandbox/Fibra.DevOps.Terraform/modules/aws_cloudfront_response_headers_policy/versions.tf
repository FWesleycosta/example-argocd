terraform {
  # optional() em object exige 1.3. Validado na 1.5.7. Testes em tests/ exigem 1.6+.
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
