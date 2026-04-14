locals {
  endpoint_type        = var.api_type == "public" ? "REGIONAL" : "PRIVATE"
  vpc_endpoint_id      = var.api_type == "private" ? var.vpc_endpoint_apigw : null
  api_key_required     = var.api_type == "public"
  domain_name_resolved = var.api_type == "public" ? module.domain_name[0].domain_name : local.full_domain_name

  redeployment_trigger_ids = concat(
    [
      module.resource_proxy.id,
      module.method_proxy.id,
      module.integration_proxy.id,
    ],
    var.api_type == "public" ? [
      module.method_root[0].id,
      module.integration_root[0].id,
    ] : [
      module.rest_api.rest_api_policy_id,
    ]
  )
}
