# Módulo `aws_cloudfront_response_headers_policy`

> Cria **uma** response headers policy do CloudFront — o conjunto de cabeçalhos (CORS, segurança,
> CSP, extras) que a CDN adiciona/remove em **toda** resposta — para ser **compartilhada** por
> várias distribuições. Pensado para a policy de plataforma `fibra-security-headers`.

**Por que compartilhada?** A conta AWS permite só **20** response headers policies. Uma por app
não escala e dá conflito de nome em migração; uma por conta, referenciada por nome pelo módulo
`aws_cloudfront_distribution` (`response_headers_policy_name`), é alterada num lugar só e vale
para todos os fronts na hora — sem redeploy.

## O que cria

| Recurso | Quando |
|---|---|
| `aws_cloudfront_response_headers_policy` | Sempre (com `create_response_headers_policy = true`, default). |

Blocos gerados conforme as variáveis: `cors_config` (`cors.enabled`), `security_headers_config`
(`security_headers.enabled`; HSTS, nosniff, X-Frame-Options, Referrer-Policy, X-XSS-Protection e
**CSP só se informado**), `custom_headers_config` (`custom_headers`), `remove_headers_config`
(`remove_headers`).

### Não faz
Não associa a policy a distribuição nenhuma (quem associa é o `aws_cloudfront_distribution`, por
nome ou ID) e não define CSP por você — `content_security_policy` vazio = não envia CSP.

## Início rápido

```hcl
module "security_headers" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_cloudfront_response_headers_policy"

  name = "fibra-security-headers"
  security_headers = {
    content_security_policy = ""          # defina quando houver inventário das origens
  }
  custom_headers = [{ header = "Permissions-Policy", value = "camera=(), microphone=(), geolocation=()" }]
  remove_headers = ["Server", "X-Powered-By"]
}
```

Os apps referenciam: `response_headers_policy_name = "fibra-security-headers"` no módulo
`aws_cloudfront_distribution` (na esteira: `cdn.response_headers_policy_name`).

## Referência

### Variáveis

| Nome | Tipo | Default | Descrição |
|---|---|---|---|
| `create_response_headers_policy` | bool | `true` | Liga/desliga o módulo. |
| `name` | string | `null` | Nome único na conta. **Obrigatório** se ligado. |
| `comment` | string | texto padrão | Comentário. |
| `cors` | object | `{ enabled=true, allow_origins=["*"], allow_methods=[GET,HEAD,OPTIONS], allow_headers=lista comum, expose_headers=[], max_age_sec=3600, allow_credentials=false, origin_override=true }` | CORS; `enabled=false` omite. |
| `security_headers` | object | `{ enabled=true, hsts_max_age_sec=31536000, hsts_include_subdomains=true, hsts_preload=false, content_type_options=true, frame_option="SAMEORIGIN", referrer_policy="strict-origin-when-cross-origin", xss_protection=true, content_security_policy="", override=true }` | Segurança; `frame_option`/`referrer_policy` = `""` omitem o header; CSP vazio omite. |
| `custom_headers` | list(object{header,value,override}) | `[]` | Cabeçalhos fixos extras. |
| `remove_headers` | list(string) | `[]` | Cabeçalhos removidos. |

Validations: `frame_option` ∈ {DENY, SAMEORIGIN, ""}; `referrer_policy` ∈ valores válidos ou "".
Preconditions: `name` obrigatório; ao menos um bloco (cors, security, custom ou remove).

### Outputs

| Nome | Descrição |
|---|---|
| `ID` | ID da policy (para `response_headers_policy_id`). |
| `Name` | Nome (para `response_headers_policy_name`). |
| `ETag` | ETag atual. |

## Testes

```bash
terraform fmt -check -recursive && terraform init -backend=false && terraform validate
terraform test      # >= 1.6; command = plan, offline
```

`tests/setup.tftest.hcl` (defaults, CSP+custom+remove, só security sem CORS, desligado) e
`tests/validations.tftest.hcl` (frame_option, referrer_policy, sem name, sem nenhum bloco).

## Limitações
Sem `server_timing_headers_config`; uma policy por chamada do módulo (use `for_each` no
chamador se precisar de variantes, lembrando da quota de 20).
