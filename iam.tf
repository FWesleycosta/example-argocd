locals {
  is_public  = var.api_type == "public"  ? 1 : 0
  is_private = var.api_type == "private" ? 1 : 0


  full_domain_name = "${var.domain_internal_name}+${var.domain_name_id}"


  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Aplicacao   = var.app_name
  }


  ssm_raw = try(jsondecode(var.ssm_parameters), [])
  ssm_params = try(jsondecode(local.ssm_raw), local.ssm_raw)

  s3_raw     = try(jsondecode(var.s3_buckets), [])
  s3_buckets = try(jsondecode(local.s3_raw), local.s3_raw)
}
 
