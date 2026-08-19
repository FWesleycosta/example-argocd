output "ID" {
  description = "ID da policy — use em response_headers_policy_id do cache behavior."
  value       = try(aws_cloudfront_response_headers_policy.this[0].id, null)
}

output "Name" {
  description = "Nome da policy — o que os apps informam em response_headers_policy_name."
  value       = try(aws_cloudfront_response_headers_policy.this[0].name, null)
}

output "ETag" {
  description = "ETag atual da policy."
  value       = try(aws_cloudfront_response_headers_policy.this[0].etag, null)
}
