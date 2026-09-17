# Só o que é transversal. Os locals de cada domínio ficam no arquivo do domínio:
#   lambda.tf · datadog.tf · iam.tf · ssm_secrets.tf · messaging.tf · step_functions.tf

locals {
  # Isola o sandbox em todo nome que não embute o ambiente (SSM e secrets usam prefixo de
  # caminho — ver ssm_secrets.tf).
  suffix = var.resource_suffix

  tags = {
    Ambiente  = var.environment
    ManagedBy = "Terraform"
    Aplicacao = var.app_name
    Projeto   = var.project_name
    Sistema   = var.sistema
    Owner     = var.owner
  }
}
