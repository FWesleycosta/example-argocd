# Módulo `aws_cloudfront_distribution`

> Cria uma distribuição **Amazon CloudFront** para servir um site estático (SPA) guardado num
> bucket S3 **privado**: acesso à origem por **OAC** (SigV4), política de headers de resposta
> (CORS + cabeçalhos de segurança), fallback de rotas de SPA e TLS 1.2+ com certificado ACM.

**O que é o CloudFront?** A "rede de entrega" da AWS: copia os arquivos do seu site para
pontos de presença perto do usuário e os entrega por HTTPS, com cache.

**E o que é este módulo?** O "formulário padrão" para pedir uma dessas distribuições apontando
para um bucket. Em vez de configurar 40 campos no console, você informa o bucket, o domínio e
o certificado — o resto vem certo (e seguro) por padrão.

---

## O que este módulo faz

| O que é criado | Em linguagem simples | Quando |
|---|---|---|
| `aws_cloudfront_origin_access_control` (OAC) | A "credencial" com que o CloudFront lê o bucket privado. Ninguém mais lê o bucket direto. | Sempre (com o módulo ligado). |
| `aws_cloudfront_response_headers_policy` | Regras de CORS + cabeçalhos de segurança (HSTS, nosniff, X-Frame-Options, Referrer-Policy) que o CloudFront adiciona a toda resposta. | Sempre; os cabeçalhos de segurança podem ser desligados (`enable_security_headers = false`). |
| `aws_cloudfront_distribution` | A distribuição em si: origem S3 via OAC, cache policy gerenciada, HTTP/2+3, redirect para HTTPS, aliases + certificado ACM, fallback SPA (403/404 → `/index.html`). | Sempre (com o módulo ligado). |

### O que o módulo não faz

| Não faz | O que isso significa na prática |
|---|---|
| Não cria o **bucket S3** nem a **bucket policy** | O root cria o bucket e a policy que permite `s3:GetObject` ao serviço `cloudfront.amazonaws.com` **condicionado ao ARN da distribuição** — use o output `ARN`. Isso evita dependência circular (bucket → distribuição → policy). |
| Não cria **registro DNS** | Aponte o CNAME/alias (`aliases`) para o output `Domain_Name` (Route 53: `Hosted_Zone_ID`). |
| Não cria/valida o **certificado ACM** | Ele precisa existir em **us-east-1** e cobrir os aliases. Passe o ARN em `acm_certificate_arn`. |
| Não faz **invalidation** | Publicação de novo conteúdo é passo de pipeline (`aws cloudfront create-invalidation`), usando o output `ID`. |
| Não configura **logging** padrão para S3 | Logs padrão do CloudFront exigem bucket com ACL habilitada (padrão antigo). Fica para versão futura (real-time logs / standard logging v2). |
| Não cria **WAF** | Só associa um Web ACL existente (`web_acl_id`, escopo CLOUDFRONT em us-east-1). |

---

## Início rápido (5 minutos)

```hcl
resource "aws_s3_bucket" "site" {
  bucket = "meu-app-dev"
}

module "cloudfront" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_cloudfront_distribution"

  name                = aws_s3_bucket.site.bucket                          # vira origin_id, oac-<name>, headers-<name>
  origin_domain_name  = aws_s3_bucket.site.bucket_regional_domain_name     # NUNCA o endpoint s3-website
  aliases             = ["meu-app-dev.bancofibra.com.br"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."  # us-east-1!
  tags                = { Ambiente = "dev" }
}

# Bucket policy no root: só o CloudFront (esta distribuição) lê o bucket.
data "aws_iam_policy_document" "bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.ARN]
    }
  }
}
```

Depois do `apply`: crie o CNAME `meu-app-dev.bancofibra.com.br → module.cloudfront.Domain_Name`.

---

## Conceitos (por que funciona assim)

- **OAC em vez de bucket público / website hosting.** O bucket fica com *public access block*
  total; só a distribuição lê, e só esta distribuição (condition `AWS:SourceArn`). Por isso o
  módulo **recusa** `origin_domain_name` de website endpoint (`s3-website-*`) — OAC exige o
  endpoint REST regional.
- **Fallback SPA em 403 *e* 404.** Com OAC e sem `s3:ListBucket`, o S3 responde **403** para
  chave inexistente (não 404). Uma SPA com rotas no cliente (`/conta/extrato`) precisa que ambos
  virem `200 /index.html`. Desligue com `spa_fallback = false` para sites que não são SPA.
- **Managed policies.** `CachingOptimized` (compressão, TTL 24h, ignora cookies/query string) e
  `CORS-S3Origin` (repassa `Origin` ao S3). O controle fino de cache fica nos **objetos**: assets
  com hash sobem com `Cache-Control: immutable`; `index.html`/`env-config.js` com `no-cache` +
  invalidation no deploy. Isso substitui o antigo `forwarded_values` (deprecado).
- **`PriceClass_All` por default.** `PriceClass_100` só cobre América do Norte/Europa — usuário
  no Brasil sairia de um edge nos EUA. Custo maior, latência menor; é decisão de negócio.
- **`create_cloudfront_distribution`.** Liga/desliga tudo com `count`; desligado, os
  obrigatórios (`name`, `origin_domain_name`) não são exigidos e os outputs viram `null` — mesmo
  padrão do módulo `aws_lambda_function`.

---

## Guias práticos

**Sem domínio próprio (só `*.cloudfront.net`)** — `aliases = []`, `acm_certificate_arn = ""`:
usa o certificado padrão do CloudFront (`cloudfront_default_certificate = true`).

**Restringir a países** — `geo_restriction = { restriction_type = "whitelist", locations = ["BR"] }`.

**Anexar WAF** — `web_acl_id = aws_wafv2_web_acl.this.arn` (Web ACL de escopo `CLOUDFRONT`,
criada em us-east-1).

**Site que não é SPA** — `spa_fallback = false` (404 volta como 404).

**Trocar cache policy** — `cache_policy_id = "<id de cache policy própria>"`; para não repassar
nada ao S3, `origin_request_policy_id = ""`.

---

## Referência completa

### Variáveis

| Nome | Tipo | Default | Descrição |
|---|---|---|---|
| `create_cloudfront_distribution` | bool | `true` | Liga/desliga o módulo. |
| `name` | string | `null` | Nome-base (origin_id, `oac-<name>`, `headers-<name>`). **Obrigatório** se ligado. |
| `origin_domain_name` | string | `null` | `bucket_regional_domain_name` do S3. **Obrigatório** se ligado. Recusa `s3-website-*`. |
| `aliases` | list(string) | `[]` | CNAMEs. Se não vazio, exige `acm_certificate_arn`. |
| `acm_certificate_arn` | string | `""` | Certificado ACM em **us-east-1**. Vazio = certificado padrão. |
| `minimum_protocol_version` | string | `TLSv1.2_2021` | TLS mínimo (com ACM). |
| `comment` | string | `""` | Vazio = primeiro alias, senão `name`. |
| `default_root_object` | string | `index.html` | Objeto de `/` e alvo do fallback SPA. |
| `price_class` | string | `PriceClass_All` | `PriceClass_All` \| `_200` \| `_100`. |
| `http_version` | string | `http2and3` | `http1.1` \| `http2` \| `http2and3` \| `http3`. |
| `is_ipv6_enabled` | bool | `true` | IPv6. |
| `allowed_methods` / `cached_methods` | list(string) | `GET,HEAD,OPTIONS` / `GET,HEAD` | Default cache behavior. |
| `cache_policy_id` | string | `658327ea-…` (CachingOptimized) | Cache policy. |
| `origin_request_policy_id` | string | `88a5eaf4-…` (CORS-S3Origin) | Origin request policy; `""` = nenhuma. |
| `cors_allowed_origins` / `_headers` / `_methods` / `cors_max_age_sec` | list / number | `["*"]` / lista comum / `GET,HEAD,OPTIONS` / `3600` | CORS da response headers policy. |
| `enable_security_headers` | bool | `true` | HSTS + nosniff + X-Frame-Options + Referrer-Policy. |
| `hsts_max_age_sec` | number | `31536000` | HSTS max-age. |
| `frame_option` | string | `SAMEORIGIN` | `DENY` \| `SAMEORIGIN`. |
| `referrer_policy` | string | `strict-origin-when-cross-origin` | Valores válidos de Referrer-Policy. |
| `spa_fallback` | bool | `true` | 403/404 → 200 `/<default_root_object>`. |
| `spa_fallback_error_caching_min_ttl` | number | `10` | TTL mínimo do cache do fallback. |
| `geo_restriction` | object | `{ none }` | `restriction_type` + `locations`. |
| `web_acl_id` | string | `""` | ARN de Web ACL (CLOUDFRONT). |
| `tags` | map(string) | `{}` | Tags da distribuição. |

### Outputs

| Nome | Descrição |
|---|---|
| `ID` | ID da distribuição (invalidation). |
| `ARN` | ARN — use na `AWS:SourceArn` da bucket policy. |
| `Domain_Name` | `*.cloudfront.net` (alvo do DNS). |
| `Hosted_Zone_ID` | Zone ID do CloudFront (alias Route 53). |
| `Origin_Access_Control_ID` | ID do OAC. |
| `Response_Headers_Policy_ID` | ID da response headers policy. |

Todos os outputs são `null` com o módulo desligado.

### Preconditions (barram o `plan`)

1. `name` obrigatório quando ligado.
2. `origin_domain_name` obrigatório quando ligado.
3. `aliases` não vazio exige `acm_certificate_arn`.
4. `origin_domain_name` não pode ser endpoint de website hosting (`s3-website-*`).

---

## Testes automatizados

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test                                   # Terraform >= 1.6
terraform test -filter=tests/preconditions.tftest.hcl
```

`tests/setup.tftest.hcl` (defaults, sem security headers/SPA, sem alias, desligado),
`tests/validations.tftest.hcl` (price_class, http_version, frame_option, referrer_policy,
geo_restriction, TLS) e `tests/preconditions.tftest.hcl` (as 4 preconditions + desligado
ignora obrigatórios). Todos com `command = plan`, credenciais falsas e `skip_*` — rodam offline.

## Limitações conhecidas

- Uma origem só (S3). Origens custom/ALB e múltiplos cache behaviors ficam fora — abra outra
  distribuição ou evolua o módulo com `ordered_cache_behavior` quando houver demanda.
- Sem logging padrão (ver "não faz").
- `web_acl_id` só associa; não cria regras.
