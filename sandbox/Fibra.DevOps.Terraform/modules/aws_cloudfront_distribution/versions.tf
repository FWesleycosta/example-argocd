terraform {
  # Piso real: optional() em object (var.geo_restriction) exige 1.3; precondition existe
  # desde a 1.2. Validado com sucesso na 1.5.7. Os testes em tests/ exigem 1.6+
  # (`terraform test`), requisito de quem desenvolve o módulo, não de quem o consome.
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.0: aws_cloudfront_origin_access_control e security_headers_config estáveis.
      # Sem teto de major para acompanhar o root que hoje pede ">= 5.0".
      version = ">= 5.0"
    }
  }
}
