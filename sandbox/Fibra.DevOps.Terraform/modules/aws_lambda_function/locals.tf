locals {
  vpc_enabled = length(coalesce(var.subnet_ids, [])) > 0 || length(coalesce(var.security_group_ids, [])) > 0

  env_vars = coalesce(var.environment, {})

  all_layers = concat(
    [for l in data.aws_lambda_layer_version.this : l.arn],
    var.layer_arns,
  )

  # Conjunto efetivo de tags, aplicado a TODOS os recursos do módulo que
  # aceitam tag (a função e o log group). É o único lugar onde tag é montada —
  # nenhum recurso lê var.tags direto.
  #
  # A base do módulo vem primeiro e var.tags por último, então o chamador
  # sempre consegue sobrescrever. O ManagedBy vive aqui, e não no default da
  # variável, justamente porque default de variável é tudo-ou-nada: quem
  # passasse tags = { Team = "..." } perdia o ManagedBy sem perceber.
  tags = merge(
    {
      ManagedBy = "Terraform"
    },
    var.tags,
  )

  # Runtime management só existe para Zip: imagem de container não tem runtime
  # gerenciado pela AWS. Não há checagem de update_runtime_on aqui porque o
  # validation da variável já garante "FunctionUpdate" como único valor
  # possível — se algum dia outro modo for liberado, este local precisa voltar
  # a filtrar "Auto", que é o default da AWS e dispensa o recurso.
  manage_runtime_config = var.create_lambda_function && var.package_type == "Zip"
}
