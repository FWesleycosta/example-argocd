output "bucket_name" {
  description = "Bucket S3 do site (alvo do aws s3 sync)"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront (vazio se cloudfront_enabled=false)"
  value       = local.cloudfront_enabled ? module.cloudfront[0].ID : ""
}

output "cloudfront_domain_name" {
  description = "Domínio *.cloudfront.net — alvo do CNAME/alias de <domain_name> no DNS (o DNS não é gerido por este root)"
  value       = local.cloudfront_enabled ? module.cloudfront[0].Domain_Name : ""
}

output "domain_name" {
  description = "Domínio público esperado da aplicação"
  value       = local.domain_name
}

output "site_url" {
  description = "URL pública do site (vazia se cloudfront_enabled=false)"
  value       = local.cloudfront_enabled ? "https://${local.domain_name}" : ""
}
