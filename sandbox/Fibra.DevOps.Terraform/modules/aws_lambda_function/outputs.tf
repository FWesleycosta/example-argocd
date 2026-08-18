output "ARN" {
  description = "ARN da Lambda function."
  value       = try(aws_lambda_function.this[0].arn, null)
}

output "Name" {
  description = "Nome da Lambda function."
  value       = try(aws_lambda_function.this[0].function_name, null)
}

output "Invoke_ARN" {
  description = "ARN de invocação, usado por API Gateway e ALB (formato diferente do ARN)."
  value       = try(aws_lambda_function.this[0].invoke_arn, null)
}

output "Qualified_ARN" {
  description = "ARN qualificado com a versão publicada."
  value       = try(aws_lambda_function.this[0].qualified_arn, null)
}

output "Version" {
  description = "Última versão publicada."
  value       = try(aws_lambda_function.this[0].version, null)
}

output "Role" {
  description = "ARN da IAM role anexada à função."
  value       = try(aws_lambda_function.this[0].role, null)
}

output "Memory" {
  description = "Memória da função em MB."
  value       = try(aws_lambda_function.this[0].memory_size, null)
}

output "Description" {
  description = "Descrição da função Lambda."
  value       = try(aws_lambda_function.this[0].description, null)
}

output "Image_URI" {
  description = "URI da imagem de container. Null quando package_type = \"Zip\"."
  value       = try(aws_lambda_function.this[0].image_uri, null)
}

output "Last_modified" {
  description = "Data da última modificação do recurso."
  value       = try(aws_lambda_function.this[0].last_modified, null)
}

output "Tags" {
  description = "Tags atribuídas à função."
  value       = try(aws_lambda_function.this[0].tags, null)
}

output "Log_group_name" {
  description = "Nome do CloudWatch Log Group gerenciado pelo módulo."
  value       = try(aws_cloudwatch_log_group.this[0].name, null)
}

output "Log_group_ARN" {
  description = "ARN do CloudWatch Log Group gerenciado pelo módulo."
  value       = try(aws_cloudwatch_log_group.this[0].arn, null)
}
