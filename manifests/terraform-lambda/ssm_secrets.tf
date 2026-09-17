########################################
# SSM Parameters / Secrets Manager
#
# Isolamento de sandbox por PREFIXO DE CAMINHO, não por sufixo. A regra de `effective_name`
# espelha manifests/terraform/locals.tf (backend) — mudou lá, mude aqui.
########################################

locals {
  ssm_params      = try([for p in try(jsondecode(var.ssm_parameters), var.ssm_parameters) : p if can(p.name)], [])
  sdx_path_prefix = local.suffix == "" ? "" : trimprefix(local.suffix, "-")

  # /dev|hml|prd/x/y -> /sdx/x/y; sem segmento de ambiente, só prefixa.
  ssm_params_named = [
    for p in local.ssm_params : merge(p, {
      effective_name = local.sdx_path_prefix == "" ? p.name : (
        length(regexall("^/(dev|hml|prd)/", p.name)) > 0
        ? replace(p.name, "/^/(dev|hml|prd)//", "/${local.sdx_path_prefix}/")
        : "/${local.sdx_path_prefix}${startswith(p.name, "/") ? "" : "/"}${p.name}"
      )
    })
  ]

  # Secrets são lista única para os ambientes (sem segmento de ambiente): sempre prefixa.
  secrets_named = [
    for s in var.resources.secrets : merge(s, {
      effective_name = local.sdx_path_prefix == "" ? s.name : (
        startswith(s.name, "/")
        ? "/${local.sdx_path_prefix}${s.name}"
        : "${local.sdx_path_prefix}/${s.name}"
      )
    })
  ]

  # Chave do for_each = nome declarado pelo app (estável entre sandbox e ambientes).
  secrets_by_name = { for s in local.secrets_named : s.name => s }
}

resource "aws_ssm_parameter" "this" {
  for_each = { for p in local.ssm_params_named : p.name => p }

  name        = each.value.effective_name
  description = try(each.value.description, "")
  type        = try(each.value.type, "String")
  value       = each.value.value
  tags        = local.tags
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets_by_name

  name                    = each.value.effective_name
  description             = each.value.description
  recovery_window_in_days = 7
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = jsonencode({ for key in local.secrets_by_name[each.key].keys : key => "PREENCHER" })

  lifecycle {
    # O valor real é preenchido fora da esteira; nunca sobrescrever.
    ignore_changes = [secret_string]
  }
}