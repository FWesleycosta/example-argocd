# manifests/terraform-lambda

**Root module** Terraform de uma aplicação **AWS Lambda** (.NET, um pacote zip com N handlers).
**Não** é template do Azure Pipelines — é copiado em runtime por `templates/deploy-lambda.yaml`
para `$(Pipeline.Workspace)/terraform`, onde a esteira gera o `backend.tf`
(`tfstate-<app>-<env>` / `<app>/terraform.tfstate`) e roda `init → validate → plan → apply`.

É o que substitui o `terraform/` que cada repositório de lambda carregava no modelo legado
(`azure-pipelines-infrastructure.yaml`): o app declara **dados** no `azure-pipelines.yml` e a
infra vem daqui, uma vez, versionada por tag da plataforma.

## O que cria

- **Funções**: uma por chave de `lambda.handlers`, todas com o mesmo pacote
  (`package/<app>.zip` do stage Build), runtime, sizing, env vars e role. Nome
  `<function_name_prefix>-<handler><suffix>`. Módulo reutilizável
  **`Fibra.DevOps.Terraform//modules/aws_lambda_function`** (cópia de trabalho em
  `sandbox/`): log group com retenção, tracing, `update_runtime_on = FunctionUpdate`.
- **IAM**: uma role por app (`lambda-<prefix><suffix>`) com `AWSLambdaBasicExecutionRole`,
  `AWSLambdaVPCAccessExecutionRole` (se VPC), `AWSXRayDaemonWriteAccess` (se `Active`) e uma
  policy inline **restrita aos recursos declarados** (SSM, secrets, filas, tópicos, state
  machines do próprio prefixo). Sem recursos declarados, sem policy inline.
- **VPC** (opcional): quando `subnetsPrivate` do ambiente está preenchido, security group só de
  egress e função anexada às subnets privadas.
- **SSM Parameters** e **Secrets Manager** (segredo criado com `PREENCHER`, valor real fora da
  esteira; `ignore_changes` no valor).
- **SQS** (com DLQ opcional e redrive), **SNS**, **assinaturas** SNS→SQS com a policy da fila.
- **Triggers** SQS→função (`aws_lambda_event_source_mapping`).
- **Step Functions** a partir de um ASL do app, renderizado com `templatefile`.
- **EventBridge Pipes** SQS→Step Function.

Recursos além da função usam **resources nativos do provider** (não os módulos git) para o root
ser validável offline; a convenção de nomes é a do legado e a que o backend usa para lookup:

| Recurso | Nome |
|---|---|
| função | `<prefix>-<handler><suffix>` |
| role / SG | `lambda-<prefix><suffix>` / `<prefix><suffix>-lambda` |
| fila / DLQ | `sqs-<env>-<region>-<queue_name><suffix>[.fifo]` |
| tópico | `sns-<env>-<region>-<topic_name><suffix>[.fifo]` |
| state machine / pipe | `<prefix>-<name><suffix>` |
| SSM / secret | prefixo de caminho `/sdx/...` no sandbox (igual ao backend) |

Referência a fila/tópico **não** declarado em `resources` vira lookup por nome
(`sqs-<env>-<region>-<nome>`, sem sufixo) — é como uma lambda consome a fila de outro app.

## Contrato com a esteira

| Origem | Variáveis |
|---|---|
| `_app.auto.tfvars.json` (gerado) | `app_name`, `project_name`, `function_name_prefix`, `package_file` |
| `_pipeline.auto.tfvars.json` (`deploy-lambda.yaml`) | `environment`, `aws_region`, `resource_suffix`, `sistema`, `owner`, `subnet_ids_csv`, `vpc_id`, `lambda`, `resources`, `environment_variables_common`, `environment_variables_env`, `ssm_parameters` |
| copiado do repo do app | `definitions/*.asl.json` (de `infra/`) |
| outputs lidos pelo motor | `function_names`, `function_arns`, `state_machine_arns` |

`lambda` e `resources` são **objetos com atributos opcionais**: o app pode omitir chaves e o
default vale (diferente do backend, onde objeto parcial substitui o default inteiro).

### ASL (Step Functions)

O arquivo em `infra/<nome>.asl.json` do app é um template: além do JSON do ASL, pode usar
`${...}` com as variáveis abaixo. Para escrever `$` literal (JSONPath) não é preciso escapar —
só a sequência `${` é interpretada; se precisar dela literal, use `$${`.

| Variável | Conteúdo |
|---|---|
| `lambda_arns["<handler>"]` / `lambda_names[...]` | ARN / nome de cada função do app |
| `sns_arns["<topic_name>"]` | ARN dos tópicos (gerenciados e externos) |
| `sqs_arns["<queue_name>"]` / `sqs_urls[...]` | ARN / URL das filas |
| `environment`, `aws_region`, `resource_suffix` | dados do ambiente |

Exemplo em `tests/fixtures/exemplo.asl.json`.

## Testes (offline)

O `init` clona o módulo do repositório privado (na esteira, `templates/infra/setup-git-auth.yaml`
configura o `GIT_PAT` antes). Para validar **local** sem acesso ao remoto, use um override
(ignorado pelo git — `**/*override.tf`) trocando o `source` pela cópia do `sandbox/`:

```hcl
# zz_source_override.tf (NÃO versionar)
module "lambda" {
  source = "../../sandbox/Fibra.DevOps.Terraform/modules/aws_lambda_function"
}
```

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test          # Terraform >= 1.7 (mock_provider); todos usam command = plan
rm zz_source_override.tf
```

Sem o zip no workdir o hash do pacote fica nulo, então plan/test não exigem artefato. Os runs
que exercitam lookup externo usam `mock_provider` (nada é consultado na AWS).
