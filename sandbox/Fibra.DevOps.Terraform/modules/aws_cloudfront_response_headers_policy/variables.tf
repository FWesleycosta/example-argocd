variable "create_response_headers_policy" {
  type        = bool
  description = "Liga/desliga o módulo. false = nada é criado e os outputs ficam null."
  default     = true
}

variable "name" {
  type        = string
  description = "Nome da policy (único na conta). Ex.: fibra-security-headers. Obrigatório quando ligado."
  default     = null
}

variable "comment" {
  type        = string
  description = "Comentário da policy."
  default     = "Security headers + CORS compartilhados (plataforma)"
}

# ---- CORS ----
variable "cors" {
  type = object({
    enabled           = optional(bool, true)
    allow_credentials = optional(bool, false)
    allow_origins     = optional(list(string), ["*"])
    allow_headers     = optional(list(string), ["Authorization", "Content-Type", "Origin", "Accept", "X-Requested-With"])
    allow_methods     = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    expose_headers    = optional(list(string), [])
    max_age_sec       = optional(number, 3600)
    origin_override   = optional(bool, true)
  })
  description = "Configuração de CORS (cors_config). enabled=false omite o bloco."
  default     = {}
}

# ---- Security headers ----
variable "security_headers" {
  type = object({
    enabled                 = optional(bool, true)
    hsts_max_age_sec        = optional(number, 31536000)
    hsts_include_subdomains = optional(bool, true)
    hsts_preload            = optional(bool, false)
    content_type_options    = optional(bool, true)
    frame_option            = optional(string, "SAMEORIGIN")                      # DENY | SAMEORIGIN | "" (omite)
    referrer_policy         = optional(string, "strict-origin-when-cross-origin") # "" omite
    xss_protection          = optional(bool, true)
    content_security_policy = optional(string, "") # vazio = não envia CSP
    override                = optional(bool, true)
  })
  description = "Cabeçalhos de segurança (security_headers_config). CSP vazio = não configurado (defina por conta/plataforma quando houver inventário de origens)."
  default     = {}

  validation {
    condition     = contains(["DENY", "SAMEORIGIN", ""], var.security_headers.frame_option)
    error_message = "security_headers.frame_option deve ser DENY, SAMEORIGIN ou \"\"."
  }
  validation {
    condition     = contains(["no-referrer", "no-referrer-when-downgrade", "origin", "origin-when-cross-origin", "same-origin", "strict-origin", "strict-origin-when-cross-origin", "unsafe-url", ""], var.security_headers.referrer_policy)
    error_message = "security_headers.referrer_policy inválido."
  }
}

# ---- Extras ----
variable "custom_headers" {
  type = list(object({
    header   = string
    value    = string
    override = optional(bool, true)
  }))
  description = "Cabeçalhos fixos adicionais (custom_headers_config), ex.: Permissions-Policy."
  default     = []
}

variable "remove_headers" {
  type        = list(string)
  description = "Cabeçalhos a remover da resposta (remove_headers_config), ex.: [\"Server\", \"X-Powered-By\"]."
  default     = []
}
