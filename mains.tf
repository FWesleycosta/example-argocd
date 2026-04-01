variable "ssm_parameters" {
  description = "Lista de parâmetros SSM a serem criados (vazio = não cria nenhum)"
  type = list(object({
    name        = string
    description = string
    type        = string
    value       = string
  }))
  default = []  # vazio = não cria nada
}


resource "aws_ssm_parameter" "this" {
  for_each = { for idx, param in var.ssm_parameters : param.name => param }

  name        = each.value.name
  description = each.value.description
  type        = each.value.type
  value       = each.value.value
  tags        = var.tags
}
