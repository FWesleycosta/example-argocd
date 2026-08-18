# manifests/terraform

**Root module** Terraform da aplicação. **Não** é template do Azure Pipelines — é
copiado em runtime pelo `templates/deploy-backend.yaml` para
`$(Build.SourcesDirectory)/terraform`, onde a esteira gera o `backend.tf` (state S3)
e roda `init` → `validate` → `apply`.

## O que mora aqui

- Os `.tf` do **root module** (ex.: `main.tf`, `variables.tf`, `outputs.tf`).
- Esses `.tf` normalmente **referenciam módulos reutilizáveis** do repositório
  separado `Fibra.DevOps/Fibra.DevOps.Terraform` via source git
  (`git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//<modulo>`).
  É por isso que `templates/infra/setup-git-auth.yaml` configura credencial git
  antes do `terraform init` — para o init conseguir clonar esses módulos.

## O que a esteira injeta (não declarar `backend` aqui)

- **`backend.tf`** é **gerado** pela esteira (bucket S3 `tfstate-<app>-<env>`, key
  `<app>/terraform.tfstate`, `encrypt = true`). Não versione `backend.tf` aqui.
- **Variáveis** chegam via `-var` / `TF_VAR_*`. O root module deve declarar:
  `app_name`, `environment`, `namespace`, `domain_name`, `cluster_name`,
  `alb_shared_dns`, `api_gateway_vpc_link`, `alb_shared_listener`, `base_path`,
  `api_type`, `vpc_endpoint_apigw`, `domain_internal_name`, `domain_name_id`,
  `cognito`, `dynamodb_tables`, `certificate_arn`,
  `ssm_parameters`, `s3_buckets`, `secrets`, `queue_name`.
