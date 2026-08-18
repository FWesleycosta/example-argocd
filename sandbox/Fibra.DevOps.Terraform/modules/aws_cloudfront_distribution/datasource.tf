# Policy de response headers COMPARTILHADA da conta, resolvida por nome (ex.: uma
# "fibra-security-headers" criada uma vez pela plataforma e usada por todas as distribuições).
data "aws_cloudfront_response_headers_policy" "shared" {
  count = local.lookup_headers_policy
  name  = var.response_headers_policy_name
}
