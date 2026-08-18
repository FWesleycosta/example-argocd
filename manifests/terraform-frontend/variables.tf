# ---- injetadas pela esteira (_app.auto.tfvars.json) ----
variable "app_name" {
  description = "Nome da aplicação (Build.Repository.Name)"
  type        = string
}

variable "bucket_name" {
  description = "Nome do bucket S3 do site: <app>-<env> (já embute o ambiente)"
  type        = string
}

variable "project_name" {
  description = "Nome do projeto no Azure DevOps (System.TeamProject)"
  type        = string
}

# ---- injetadas pela esteira (_pipeline.auto.tfvars.json / deploy-frontend.yaml) ----
variable "environment" {
  description = "Ambiente: dev, hml, prd, sdx"
  type        = string
}

variable "aws_region" {
  description = "Região do bucket (a distribuição CloudFront é global; o certificado ACM é sempre lido em us-east-1)"
  type        = string
}

variable "dns_name" {
  description = "Subdomínio da aplicação. Domínio final: <dns_name>-<env>.<base_domain> (prd: <dns_name>.<base_domain>)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.dns_name))
    error_message = "dns_name deve ser um label DNS válido (minúsculas, dígitos e hífens; sem começar/terminar com hífen)."
  }
}

variable "cloudfront_enabled" {
  description = "Cria distribuição CloudFront + OAC + policy do bucket. Azure DevOps interpola booleanos como True/False — comparação case-insensitive."
  type        = string
  default     = "true"
}

variable "access_logging_bucket" {
  description = "Bucket de access logging da conta (variables/env/<env>.yaml: accessLoggingWorkloads). Vazio = sem logging."
  type        = string
  default     = ""
}

variable "resource_suffix" {
  description = "Sufixo de sandbox (sdx envia -sdx; um valor customizado isola outro sandbox do mesmo app, como no EKS). Quando não vazio, substitui -<env> no domínio (<dns_name><suffix>.<base_domain>); o bucket já chega sufixado pela esteira. Vazio em dev/hml/prd."
  type        = string
  default     = ""
}

variable "sistema" {
  description = "Sistema/dominio de negocio (tag de governanca)"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Time/pessoa responsavel (tag de governanca)"
  type        = string
  default     = ""
}

# ---- opcionais (defaults da plataforma) ----
variable "base_domain" {
  description = "Domínio base público"
  type        = string
  default     = "bancofibra.com.br"
}

variable "acm_certificate_arn" {
  description = "ARN de certificado ACM em us-east-1. Vazio = lookup do certificado ISSUED mais recente para acm_certificate_domain."
  type        = string
  default     = ""
}

variable "acm_certificate_domain" {
  description = "Domínio usado no lookup do certificado ACM quando acm_certificate_arn está vazio"
  type        = string
  default     = "*.bancofibra.com.br"
}

variable "price_class" {
  description = "Price class do CloudFront. PriceClass_100 NÃO inclui edges na América do Sul — mantenha PriceClass_All para usuários no Brasil."
  type        = string
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class deve ser PriceClass_All, PriceClass_200 ou PriceClass_100."
  }
}

variable "response_headers_policy_name" {
  description = "Nome da response headers policy COMPARTILHADA da conta (security headers da plataforma), resolvida por nome pelo módulo. Vazio = managed da AWS Managed-CORS-and-SecurityHeadersPolicy. O módulo NÃO cria policy por distribuição (quota de 20/conta)."
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "Origens permitidas na response headers policy (CORS) aplicada a *.js"
  type        = list(string)
  default     = ["*"]
}
