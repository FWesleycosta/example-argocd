terraform {
  # Piso real, verificado — não o que a documentação antiga afirmava (1.9.0).
  # O recurso mais novo que o módulo usa é optional() em tipo object
  # (var.layers), disponível desde a 1.3; precondition existe desde a 1.2.
  # O módulo foi validado com sucesso na 1.5.7.
  #
  # Os testes em tests/ exigem 1.6+ (comando `terraform test`), mas isso é
  # requisito de quem desenvolve o módulo, não de quem o consome — por isso
  # não entra neste piso.
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Operador pessimista: aceita 6.x, barra o 7.0. A versão em uso hoje
      # nos testes é a 6.56.0.
      version = "~> 6.0"
    }
  }
}
