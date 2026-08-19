output "ID" {
  description = "ID da distribuição (usado no create-invalidation)."
  value       = try(aws_cloudfront_distribution.this[0].id, null)
}

output "ARN" {
  description = "ARN da distribuição — use na condition AWS:SourceArn da bucket policy do S3 (OAC)."
  value       = try(aws_cloudfront_distribution.this[0].arn, null)
}

output "Domain_Name" {
  description = "Domínio *.cloudfront.net — alvo do CNAME/alias no DNS."
  value       = try(aws_cloudfront_distribution.this[0].domain_name, null)
}

output "Hosted_Zone_ID" {
  description = "Hosted zone ID do CloudFront (para registro alias no Route 53)."
  value       = try(aws_cloudfront_distribution.this[0].hosted_zone_id, null)
}

output "Origin_Access_Control_ID" {
  description = "ID do OAC criado."
  value       = try(aws_cloudfront_origin_access_control.this[0].id, null)
}

output "Response_Headers_Policy_ID" {
  description = "ID da response headers policy criada."
  value       = try(aws_cloudfront_response_headers_policy.this[0].id, null)
}
