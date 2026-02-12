# Terraform Module — AWS Step Functions

Módulo Terraform para provisionamento de **AWS Step Functions (State Machines)** seguindo boas práticas.

## Recursos Criados

| Recurso | Descrição |
|---------|-----------|
| `aws_sfn_state_machine` | State Machine principal |
| `aws_iam_role` | IAM Role com assume role restrito por account ID |
| `aws_iam_role_policy` | Política de logging (condicional) |
| `aws_iam_role_policy_attachment` | Políticas adicionais customizáveis |
| `aws_cloudwatch_log_group` | Log Group para a State Machine (condicional) |

## Boas Práticas Aplicadas

- **Separação de arquivos**: `main.tf`, `iam.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `data.tf`
- **Variáveis tipadas com validações**: garante inputs corretos em tempo de plan
- **Blocos dinâmicos**: logging e tracing opcionais sem duplicação de código
- **Least privilege IAM**: assume role com condition `aws:SourceAccount`
- **Tags padrão**: tag `ManagedBy = Terraform` aplicada automaticamente
- **Versionamento de providers**: constraints mínimas definidas
- **Exemplo de uso**: pasta `examples/basic/`

## Uso Básico

```hcl
module "step_function" {
  source = "./terraform-step-functions"

  name = "minha-state-machine"

  definition = jsonencode({
    Comment = "Exemplo"
    StartAt = "HelloWorld"
    States = {
      HelloWorld = {
        Type   = "Pass"
        Result = "Hello!"
        End    = true
      }
    }
  })

  tags = {
    Environment = "dev"
  }
}
```

## Inputs

| Nome | Tipo | Default | Descrição |
|------|------|---------|-----------|
| `name` | `string` | — | Nome da State Machine |
| `definition` | `string` | — | JSON da definição (ASL) |
| `type` | `string` | `"STANDARD"` | STANDARD ou EXPRESS |
| `tags` | `map(string)` | `{}` | Tags dos recursos |
| `create_log_group` | `bool` | `false` | Criar CloudWatch Log Group |
| `log_retention_in_days` | `number` | `30` | Retenção de logs |
| `logging_configuration` | `object` | `null` | Configuração de logging |
| `kms_key_id` | `string` | `null` | KMS para encriptar logs |
| `tracing_enabled` | `bool` | `false` | Habilitar X-Ray |
| `additional_policy_arns` | `list(string)` | `[]` | Políticas IAM extras |

## Outputs

| Nome | Descrição |
|------|-----------|
| `state_machine_arn` | ARN da State Machine |
| `state_machine_id` | ID da State Machine |
| `state_machine_name` | Nome da State Machine |
| `role_arn` | ARN da IAM Role |
| `role_name` | Nome da IAM Role |
| `log_group_arn` | ARN do Log Group |
