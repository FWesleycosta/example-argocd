# manifests/terraform-frontend

**Root module** Terraform de uma aplicação **frontend SPA** (S3 + CloudFront). **Não** é
template do Azure Pipelines — é copiado em runtime por `templates/deploy-frontend.yaml`
para `$(Build.SourcesDirectory)/terraform`, onde a esteira gera o `backend.tf`
(`tfstate-<app>-<env>` / `<app>/terraform.tfstate`) e roda `init → validate → plan → apply`.

## O que cria

- **S3** `var.bucket_name` (= `<app>-<env>`): privado (public access block), versioning,
  SSE-S3, `BucketOwnerEnforced`, access logging em `access_logging_bucket` (se informado),
  policy com *deny* sem TLS + leitura pelo CloudFront (OAC, restrita ao ARN da distribuição).
- **CloudFront** (`cloudfront_enabled`, default `true`) via módulo reutilizável
  **`Fibra.DevOps.Terraform//modules/aws_cloudfront_distribution`** (`source = "git::https://..."`,
  cópia de trabalho em `sandbox/Fibra.DevOps.Terraform/modules/aws_cloudfront_distribution`):
  OAC, security headers via policy **compartilhada** (`response_headers_policy_name`, resolvida
  por nome; vazio = managed AWS `CORS-and-SecurityHeadersPolicy` — nunca uma policy por app),
  managed policies `CachingOptimized` + `CORS-S3Origin`, alias `<dns_name>-<env>.<base_domain>`
  (prd: `<dns_name>.<base_domain>`), fallback SPA 403/404 → `/index.html`, TLS 1.2+.
  A bucket policy (OAC restrito ao `module.cloudfront[0].ARN`) fica aqui no root.
- Certificado: `acm_certificate_arn` ou lookup do wildcard `acm_certificate_domain` em
  **us-east-1**.

**Não** cria registro DNS: aponte `domain_name` (output) para `cloudfront_domain_name`.

## Contrato com a esteira

| Origem | Variáveis |
|---|---|
| `_app.auto.tfvars.json` (gerado) | `app_name`, `bucket_name`, `project_name` |
| `_pipeline.auto.tfvars.json` (`deploy-frontend.yaml`) | `environment`, `aws_region`, `resource_suffix`, `sistema`, `owner`, `dns_name`, `cloudfront_enabled`, `response_headers_policy_name`, `access_logging_bucket` |
| outputs lidos pelo motor | `bucket_name`, `cloudfront_distribution_id`, `site_url` |

**Sandbox (`sdx`)**: a esteira envia `resource_suffix` (`-sdx` por default, ou o valor
customizado de `resourceSuffix` no app) e já sufixa o `bucket_name` (`<app><suffix>`); aqui
o sufixo substitui `-<env>` no domínio (`<dns_name><suffix>.<base_domain>`). Sufixo
customizado = outro sandbox isolado do mesmo app (bucket, domínio e state próprios), como no
EKS. Nunca versione `backend.tf` aqui.

## Testes (offline)

O `init` clona o módulo do repositório privado (na esteira, `templates/infra/setup-git-auth.yaml`
configura o `GIT_PAT` antes). Para validar **local** sem acesso ao remoto, use um override
(ignorado pelo git — `**/*_override.tf`) trocando o `source` pela cópia do `sandbox/`:

```hcl
# zz_source_override.tf (NÃO versionar)
module "cloudfront" {
  source = "../../sandbox/Fibra.DevOps.Terraform/modules/aws_cloudfront_distribution"
}
```

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test          # Terraform >= 1.6; todos usam command = plan e credenciais falsas
rm zz_source_override.tf
```
