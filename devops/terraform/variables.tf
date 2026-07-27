
variable "function_name" {
  type        = string
  description = "The name of the AWS Lambda function."
  default     = null
}

variable "role" {
  type        = string
  description = "ARN ou nome da IAM role da Lambda. Com Datadog habilitado, o módulo anexa política inline de leitura do secret `datadog/api-key` (GetSecretValue + DescribeSecret nesse ARN)."
  default     = null
}

variable "memory_size" {
  type        = number
  description = "The amount of memory allocated to the Lambda function in MB."
  default     = 128
}

variable "timeout" {
  type        = number
  description = "The maximum execution time of the Lambda function in seconds."
  default     = 30
}

variable "handler" {
  type        = string
  description = "The function handler that Lambda calls to begin execution."
  default     = null
}

variable "description" {
  type        = string
  description = "A description of the AWS Lambda function."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Defines tags to manage and control resources within the AWS environment."
  default = {
    ManagedBy = "Terraform"
  }
}

variable "package_type" {
  type        = string
  description = "The packaging type of the Lambda function (e.g., Zip or Image)."
  default     = "Zip"

  validation {
    condition = contains(["Zip", "Image"], var.package_type)
    error_message = "The packaging type of the 'Zip' or 'Image'."
  }
}

variable "runtime" {
  type        = string
  description = "The runtime environment for the Lambda function."
  default     = null
}

variable "publish" {
  type        = bool
  description = "Determines whether to publish creation or updates of the Lambda function."
  default     = true
}

variable "filename" {
  type        = string
  description = "The path to the function's deployment package within the local filesystem."
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Used to trigger updates in Lambda when the source code changes."
  default     = null
}

variable "ephemeral_storage" {
  type        = number
  description = "The size of ephemeral storage allocated for the Lambda function in MB."
  default     = 512
}

variable "create_lambda_function" {
  description = "Whether to create the lambda function"
  type        = bool
  default     = true
}

variable "environment" {
  description = "A map of environment variables that will be provided to the Lambda function. This allows you to dynamically adjust the runtime environment of your function without modifying the underlying code. Each environment variable is a key-value pair that can be used within the Lambda function to adapt its behavior or to provide essential configuration information."
  type        = map(string)
  default     = null
}


variable "tracing_config" {
  description = "The tracing configuration for the Lambda function. Specify 'Active' to enable X-Ray tracing or 'PassThrough' to use the tracing setting from the calling service."
  type        = string
  default     = "Active"
}

variable "security_group_ids" {
  description = "A list of security group IDs to associate with the Lambda function."
  type        = list(string)
  default     = null
}

variable "subnet_ids" {
  description = "A list of subnet IDs to associate with the Lambda function."
  type        = list(string)
  default     = null
}

variable "log_retention_days" {
  description = "The number of days to retain the logs in CloudWatch Logs. Valid values are: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, and 400."
  type        = number
  default     = null
}

variable "layers" {
  type = list(object({
    name    = string
    version = optional(number)
  }))
  default = []
}

variable "layer_arns" {
  description = "ARNs de layers externas ou públicas para adicionar diretamente, sem data source."
  type        = list(string)
  default     = []
}
 
