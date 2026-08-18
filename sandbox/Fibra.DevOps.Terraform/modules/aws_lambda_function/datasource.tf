data "aws_lambda_layer_version" "this" {
  for_each   = { for l in var.layers : l.name => l }
  layer_name = each.value.name
  version    = lookup(each.value, "version", null)
}