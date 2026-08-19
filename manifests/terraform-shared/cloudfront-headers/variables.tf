variable "aws_region" {
  description = "Região usada pelo provider (CloudFront é global)"
  type        = string
}

variable "environment" {
  description = "Conta/ambiente onde a policy é criada (dev, hml, prd) — só para tags/comentário"
  type        = string
}

variable "policy_name" {
  description = "Nome da policy compartilhada. Os apps referenciam este nome em cdn.response_headers_policy_name (default da esteira: fibra-security-headers)."
  type        = string
  default     = "fibra-security-headers"
}

variable "content_security_policy" {
  description = "CSP da plataforma. Vazio = não envia CSP (defina quando houver inventário das origens usadas pelos fronts)."
  type        = string
  default     = ""
}

variable "cors_allow_origins" {
  description = "Origens permitidas no CORS dos assets estáticos"
  type        = list(string)
  default     = ["*"]
}

variable "remove_headers" {
  description = "Cabeçalhos removidos da resposta"
  type        = list(string)
  default     = ["Server", "X-Powered-By"]
}

variable "custom_headers" {
  description = "Cabeçalhos fixos adicionais"
  type = list(object({
    header   = string
    value    = string
    override = optional(bool, true)
  }))
  default = [
    { header = "Permissions-Policy", value = "camera=(), microphone=(), geolocation=()" }
  ]
}
