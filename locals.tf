locals {
  domain_name = var.ENVIRONMENT == "prd" ? "${var.APP_NAME}.bancofibra.com.br" : "${var.APP_NAME}-${var.ENVIRONMENT}.bancofibra.com.br"
}
 
