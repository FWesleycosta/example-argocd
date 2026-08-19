# Policy de response headers COMPARTILHADA da conta: criada UMA vez por ambiente (dev/hml/prd)
# pela plataforma e referenciada por nome por todas as distribuições do stack spa-frontend
# (cdn.response_headers_policy_name). Nunca crie policy por app — quota de 20 por conta.
module "security_headers" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_cloudfront_response_headers_policy"

  name    = var.policy_name
  comment = "Security headers + CORS compartilhados da plataforma (${var.environment})"

  cors = {
    allow_origins = var.cors_allow_origins
  }
  security_headers = {
    content_security_policy = var.content_security_policy
  }
  custom_headers = var.custom_headers
  remove_headers = var.remove_headers
}
