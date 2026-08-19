# manifests/terraform-shared/cloudfront-headers

Root **de plataforma** (não é por app): cria a response headers policy **compartilhada**
`fibra-security-headers` (HSTS 1 ano, nosniff, X-Frame-Options SAMEORIGIN, Referrer-Policy,
X-XSS-Protection, CSP opcional, `Permissions-Policy`, remove `Server`/`X-Powered-By`, CORS para
assets) via módulo `Fibra.DevOps.Terraform//modules/aws_cloudfront_response_headers_policy`.

Todas as distribuições do stack `spa-frontend` referenciam essa policy **por nome**
(`cdn.response_headers_policy_name`, default `fibra-security-headers`). A conta tem quota de
**20** response headers policies — por isso uma só, compartilhada, em vez de uma por app.

## Aplicar (uma vez por conta/ambiente — dev, hml, prd)

```bash
cd manifests/terraform-shared/cloudfront-headers
terraform init \
  -backend-config="bucket=tfstate-platform-dev" \
  -backend-config="key=cloudfront-headers/terraform.tfstate" \
  -backend-config="region=us-east-2" -backend-config="encrypt=true"
terraform apply -var environment=dev -var aws_region=us-east-2
```

(repita para hml/prd com a service connection/credencial da conta correspondente). Mudar CSP
ou headers: altere aqui e reaplique — **todas** as distribuições recebem na hora, sem redeploy
dos apps.

Enquanto a policy não existir na conta, o `Deploy_<env>` do frontend falha cedo com mensagem
explícita (checagem antes do Terraform). Para um app sair do padrão (ex.: CSP própria), ele pode
apontar `cdn.response_headers_policy_name` para outra policy existente ou `''` para a managed da
AWS.
