output "Last_modified" {
  description = "Date this resource was last modified."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].last_modified : ""
}

output "ARN" {
  description = "Amazon Resource Name (ARN) identifying your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].arn : ""
}

output "Version" {
  description = "Latest published version of your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].version : ""
}

output "Timeouts" {
  description = "Amount of time your Lambda Function has to run in seconds."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].timeouts : null
}

output "Name" {
  description = "Date this resource was last modified."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].function_name : ""
}

output "Role" {
  description = "The IAM role attached to your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].role : ""
}

output "Memory" {
  description = "Amount of memory your Lambda Function has in MB."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].memory_size : null
}

output "Description" {
  description = "Description of your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].description : ""
}

output "Image_URI" {
  description = "URI of the container image used for your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].image_uri : ""
}

output "Tags" {
  description = "Tags assigned to your Lambda Function."
  value       = length(aws_lambda_function.this) > 0 ? aws_lambda_function.this[0].tags : {}
}
