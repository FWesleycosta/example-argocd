variable "create_cloudfront_distribution" {
  type        = bool
  description = "Liga/desliga o módulo inteiro (distribuição, OAC e response headers policy). false = nada é criado e todos os outputs ficam null."
  default     = true
}

variable "name" {
  type        = string
  description = "Nome-base dos recursos: origin_id da distribuição, OAC (`oac-<name>`) e response headers policy (`headers-<name>`). Use o nome do bucket de origem — ele já embute ambiente/sufixo. Obrigatório quando create_cloudfront_distribution = true."
  default     = null
}

variable "origin_domain_name" {
  type        = string
  description = "Domínio regional do bucket S3 de origem (aws_s3_bucket.x.bucket_regional_domain_name). Não use o endpoint de website hosting: o acesso é privado, via OAC (SigV4). Obrigatório quando create_cloudfront_distribution = true."
  default     = null
}

variable "aliases" {
  type        = list(string)
  description = "CNAMEs públicos da distribuição (ex.: [\"app-dev.bancofibra.com.br\"]). Se não vazio, acm_certificate_arn é obrigatório. O módulo NÃO cria o registro DNS."
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN de certificado ACM emitido em us-east-1 (exigência do CloudFront) cobrindo os aliases. Vazio = certificado padrão *.cloudfront.net (só faz sentido sem aliases)."
  default     = ""
}

variable "minimum_protocol_version" {
  type        = string
  description = "Versão mínima de TLS para viewers. Só se aplica com certificado ACM (aliases)."
  default     = "TLSv1.2_2021"

  validation {
    condition     = contains(["TLSv1.2_2021", "TLSv1.2_2019", "TLSv1.2_2018", "TLSv1.1_2016", "TLSv1_2016", "TLSv1"], var.minimum_protocol_version)
    error_message = "minimum_protocol_version inválido. Use TLSv1.2_2021 (recomendado) ou outro valor aceito pelo CloudFront."
  }
}

variable "comment" {
  type        = string
  description = "Comentário da distribuição (aparece no console). Vazio = primeiro alias, ou name."
  default     = ""
}

variable "default_root_object" {
  type        = string
  description = "Objeto servido em `/`."
  default     = "index.html"
}

variable "price_class" {
  type        = string
  description = "Price class. PriceClass_100 NÃO inclui edges na América do Sul — para usuários no Brasil mantenha PriceClass_All."
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class deve ser PriceClass_All, PriceClass_200 ou PriceClass_100."
  }
}

variable "http_version" {
  type        = string
  description = "Versão HTTP máxima aceita dos viewers."
  default     = "http2and3"

  validation {
    condition     = contains(["http1.1", "http2", "http2and3", "http3"], var.http_version)
    error_message = "http_version deve ser http1.1, http2, http2and3 ou http3."
  }
}

variable "is_ipv6_enabled" {
  type        = bool
  description = "Habilita IPv6 na distribuição."
  default     = true
}

variable "allowed_methods" {
  type        = list(string)
  description = "Métodos aceitos pelo default cache behavior. Para SPA estática, GET/HEAD/OPTIONS bastam."
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cached_methods" {
  type        = list(string)
  description = "Métodos cacheados pelo default cache behavior."
  default     = ["GET", "HEAD"]
}

variable "cache_policy_id" {
  type        = string
  description = "ID da cache policy. Default: managed CachingOptimized (compressão + TTL 24h, sem cookies/query string). Assets com hash devem vir do S3 com Cache-Control immutable; index.html com no-cache + invalidation no deploy."
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "origin_request_policy_id" {
  type        = string
  description = "ID da origin request policy. Default: managed CORS-S3Origin (repassa Origin e headers de CORS ao S3). Vazio = nenhuma."
  default     = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Origens permitidas na response headers policy (CORS). [\"*\"] libera qualquer origem — adequado para assets estáticos públicos."
  default     = ["*"]
}

variable "cors_allowed_headers" {
  type        = list(string)
  description = "Headers permitidos no CORS."
  default     = ["Authorization", "Content-Type", "Origin", "Accept", "X-Requested-With"]
}

variable "cors_allowed_methods" {
  type        = list(string)
  description = "Métodos permitidos no CORS."
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cors_max_age_sec" {
  type        = number
  description = "Access-Control-Max-Age (segundos)."
  default     = 3600
}

variable "enable_security_headers" {
  type        = bool
  description = "Adiciona HSTS, X-Content-Type-Options, X-Frame-Options e Referrer-Policy na response headers policy."
  default     = true
}

variable "hsts_max_age_sec" {
  type        = number
  description = "max-age do Strict-Transport-Security (segundos)."
  default     = 31536000
}

variable "frame_option" {
  type        = string
  description = "Valor de X-Frame-Options."
  default     = "SAMEORIGIN"

  validation {
    condition     = contains(["DENY", "SAMEORIGIN"], var.frame_option)
    error_message = "frame_option deve ser DENY ou SAMEORIGIN."
  }
}

variable "referrer_policy" {
  type        = string
  description = "Valor de Referrer-Policy."
  default     = "strict-origin-when-cross-origin"

  validation {
    condition     = contains(["no-referrer", "no-referrer-when-downgrade", "origin", "origin-when-cross-origin", "same-origin", "strict-origin", "strict-origin-when-cross-origin", "unsafe-url"], var.referrer_policy)
    error_message = "referrer_policy inválido."
  }
}

variable "spa_fallback" {
  type        = bool
  description = "SPA com roteamento no cliente: responde 403 e 404 da origem com 200 + /<default_root_object>. Com OAC (sem s3:ListBucket) o S3 devolve 403 para chave inexistente — por isso os dois códigos."
  default     = true
}

variable "spa_fallback_error_caching_min_ttl" {
  type        = number
  description = "TTL mínimo (segundos) de cache das respostas de erro reescritas pelo fallback."
  default     = 10
}

variable "geo_restriction" {
  type = object({
    restriction_type = optional(string, "none")
    locations        = optional(list(string), [])
  })
  description = "Restrição geográfica (none | whitelist | blacklist + lista de países ISO 3166-1 alpha-2)."
  default     = {}

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction.restriction_type)
    error_message = "geo_restriction.restriction_type deve ser none, whitelist ou blacklist."
  }
}

variable "web_acl_id" {
  type        = string
  description = "ARN de Web ACL do WAFv2 (escopo CLOUDFRONT, us-east-1) a associar. Vazio = sem WAF."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags aplicadas à distribuição."
  default     = {}
}
