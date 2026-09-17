output "function_names" {
  description = "Nome final de cada função, por chave de handler."
  value       = local.function_names
}

output "function_arns" {
  description = "ARN de cada função, por chave de handler."
  value       = local.lambda_arns
}

output "role_arn" {
  description = "Role de execução compartilhada pelas funções."
  value       = aws_iam_role.lambda.arn
}

output "queue_urls" {
  description = "URLs das filas gerenciadas, por queue_name lógico."
  value       = { for name, q in aws_sqs_queue.this : name => q.url }
}

output "topic_arns" {
  description = "ARNs dos tópicos gerenciados, por topic_name lógico."
  value       = { for name, t in aws_sns_topic.this : name => t.arn }
}

output "state_machine_arns" {
  description = "ARNs das state machines, por name lógico."
  value       = { for name, s in aws_sfn_state_machine.this : name => s.arn }
}
