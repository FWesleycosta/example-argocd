╷
│ Error: creating API Gateway REST API (fibra-corporativo-dados-mercado-api-v2-teste): operation error API Gateway: CreateRestApi, https response error StatusCode: 400, RequestID: b0d642e5-14fc-49a5-958c-71a224876d4d, BadRequestException: Endpoint access mode is not supported for this security policy
│
│   with aws_api_gateway_rest_api.this[0],
│   on main.tf line 439, in resource "aws_api_gateway_rest_api" "this":
│ 439: resource "aws_api_gateway_rest_api" "this" {
│
╵
Erros toleráveis: 0 | Outros: 1
