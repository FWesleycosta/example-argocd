variable "app_name" {
    description = "Nome da aplicação (vem do repositório)"
    type = string
}

variable "namespace" {
    description = "Nome do namespace onde a aplicação vai rodar no EKS"
    type = string
}

variable "alb_shared_dns" {
  type    = string
}

variable "api_gateway_vpc_link" {
  type    = string
  default = "kzeyja"
}

variable "alb_shared_listener" {
  type    = string
}

variable "domain_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "base_path" {
  type = string
}

variable "api_type" {
  description = "public or private"
  type = string
  default = "private"
}

variable "vpc_endpoint_apigw" {
  type    = string
}

variable "domain_internal_name" {
  type = string
}

variable "domain_name_id" {
  type = string
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ssm_parameters" {
  type = string
  default = "[]"
}

variable "dynamodb_tables" {
  description = "Lista de tabelas DynamoDB a serem criadas"
  type = list(object({
    table_name               = string
    billing_mode             = optional(string, "PAY_PER_REQUEST")
    hash_key                 = string
    range_key                = optional(string)
    attributes               = list(object({ name = string, type = string }))
    global_secondary_indexes = optional(list(object({
      name               = string
      hash_key           = string
      range_key          = optional(string)
      projection_type    = optional(string, "ALL")
      non_key_attributes = optional(list(string))
      read_capacity      = optional(number)
      write_capacity     = optional(number)
    })), [])
  }))
  default = []
}

variable "s3_buckets" {
  description = "Lista de buckets S3 a serem criados"
  type = string
  default = "[]"
}

locals {
    is_public  = var.api_type == "public"   ? 1 : 0 
    is_private = var.api_type == "private" ? 1 : 0
}

locals {
    full_domain_name = "${var.domain_internal_name}+${var.domain_name_id}"
}

locals {
  tags = {
    Environment = var.environment
    Created_at  = formatdate("DD-MM-YYYY HH:mm:ss 'BRT'", timeadd(timestamp(), "-3h"))
    ManagedBy   = "Terraform"
    Aplicacao   = var.app_name
  }
}


locals {

  ssm_raw = try(jsondecode(var.ssm_parameters), [])
  ssm_params = try(jsondecode(local.ssm_raw), local.ssm_raw)

  s3_raw     = try(jsondecode(var.s3_buckets), [])
  s3_buckets = try(jsondecode(local.s3_raw), local.s3_raw)

}


resource "aws_iam_role" "app_name" {
  name = "eks-pod-identity-${var.app_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}


resource "aws_iam_policy" "app_name" {
  name        = "eks-pod-${var.app_name}"
  description = "Permite ao pod acesso em todos os serviços/recursos da conta"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Services"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sns:Publish",
          "sns:Subscribe",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "ssm:GetParametersByPath",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ses:SendEmail",
          "events:PutEvents",
          "events:PutRule",
          "events:PutTargets",
          "events:DescribeRule",
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration",
          "states:StartExecution",
          "states:StopExecution",
          "states:DescribeExecution",
          "states:GetExecutionHistory",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ],
        Condition = {
          "StringEquals": {
            "aws:ResourceTag/Aplicacao" = var.app_name
          }
        }
        Resource = "*"
      },
      {
        Sid = "SSMByPath"
        Effect = "Allow"
        Action = [
          "ssm:GetParametersByPath",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetObject",
          "ses:SendEmail",
          "s3:DeleteObject",
          "sqs:sendmessage",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "app_name" {
  role       = aws_iam_role.app_name.name
  policy_arn = aws_iam_policy.app_name.arn
}

resource "aws_eks_pod_identity_association" "app_name" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "default"
  role_arn        = aws_iam_role.app_name.arn
}

######################################
#             API gateway
#####################################

#################################
# CUSTOM DOMAIN (DATA SOURCE)
#################################
data "aws_api_gateway_domain_name" "api_bancofibra_com_br" {
  count = local.is_public
  domain_name = var.domain_name
}

#################################
# CLOUDWATCH LOG GROUP
#################################
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${var.app_name}"
  retention_in_days = 1
}

#################################
# REST API
#################################
resource "aws_api_gateway_rest_api" "app_name" {
  count = local.is_public
  name        = var.app_name
  description = var.app_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }


  tags = {
    name = "var.app_name"
  }

}

#################################
# RESOURCE /{proxy+}
#################################
resource "aws_api_gateway_resource" "proxy" {
  count       = local.is_public
  rest_api_id = aws_api_gateway_rest_api.app_name[count.index].id
  parent_id   = aws_api_gateway_rest_api.app_name[count.index].root_resource_id
  path_part   = "{proxy+}"
}


#################################
# METHOD ANY
#################################
resource "aws_api_gateway_method" "proxy" {
  count            = local.is_public
  rest_api_id      = aws_api_gateway_rest_api.app_name[count.index].id
  resource_id      = aws_api_gateway_resource.proxy[count.index].id
  http_method      = "ANY"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

#################################
# INTEGRATION -> ALB via VPC LINK
#################################
resource "aws_api_gateway_integration" "proxy" {
  count       = local.is_public
  rest_api_id = aws_api_gateway_rest_api.app_name[count.index].id
  resource_id = aws_api_gateway_resource.proxy[count.index].id
  http_method = aws_api_gateway_method.proxy[count.index].http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${var.alb_shared_dns}:80/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = var.api_gateway_vpc_link
  integration_target      = var.alb_shared_listener

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

#################################
# DEPLOYMENT (OBRIGATÓRIO NO REST)
#################################
resource "aws_api_gateway_deployment" "app_name" {
  count       = local.is_public
  rest_api_id = aws_api_gateway_rest_api.app_name[count.index].id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.proxy[count.index].id,
      aws_api_gateway_method.proxy[count.index].id,
      aws_api_gateway_integration.proxy[count.index].id,
      aws_api_gateway_method.root[count.index].id,
      aws_api_gateway_integration.root[count.index].id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

#################################
# STAGE + ACCESS LOGS
#################################
resource "aws_api_gateway_stage" "default" {
  count         = local.is_public
  rest_api_id   = aws_api_gateway_rest_api.app_name[count.index].id
  deployment_id = aws_api_gateway_deployment.app_name[count.index].id
  stage_name    = "default"

#  access_log_settings {
#    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
#    format = jsonencode({
#      requestId        = "$context.requestId"
#      sourceIp         = "$context.identity.sourceIp"
#      requestTime      = "$context.requestTime"
#      httpMethod       = "$context.httpMethod"
#      resourcePath     = "$context.resourcePath"
#      status           = "$context.status"
#      responseLength   = "$context.responseLength"
#      integrationError = "$context.integration.error"
#    })
#  }
}

#################################
# BASE PATH MAPPING
#################################
resource "aws_api_gateway_base_path_mapping" "app_name" {
  count       = local.is_public
  api_id      = aws_api_gateway_rest_api.app_name[count.index].id
  stage_name  = aws_api_gateway_stage.default[count.index].stage_name
  domain_name = data.aws_api_gateway_domain_name.api_bancofibra_com_br[count.index].domain_name
  base_path   = var.base_path
}

#################################
# USAGE PLAN
#################################

resource "aws_api_gateway_usage_plan" "app_name" {
  count       = local.is_public
  name        = var.app_name
  description = "Usage plan ${var.app_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.app_name[count.index].id
    stage  = aws_api_gateway_stage.default[count.index].stage_name
  }
  tags               = local.tags
}

#################################
# API KEY
#################################
resource "aws_api_gateway_api_key" "app_name" {
  count       = local.is_public
  name        = var.app_name
  description = "API Key para ${var.app_name}"
  enabled     = true
  tags               = local.tags

}

#################################
# USAGE PLAN ↔ API KEY
#################################
resource "aws_api_gateway_usage_plan_key" "app_name" {
  count         = local.is_public
  key_id        = aws_api_gateway_api_key.app_name[count.index].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.app_name[count.index].id
}


resource "aws_api_gateway_method" "root" {
  count            = local.is_public
  rest_api_id      = aws_api_gateway_rest_api.app_name[count.index].id
  resource_id      = aws_api_gateway_rest_api.app_name[count.index].root_resource_id
  http_method      = "ANY"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "root" {
  count       = local.is_public
  rest_api_id = aws_api_gateway_rest_api.app_name[count.index].id
  resource_id = aws_api_gateway_rest_api.app_name[count.index].root_resource_id
  http_method = aws_api_gateway_method.root[count.index].http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${var.alb_shared_dns}:80"
  connection_type         = "VPC_LINK"
  connection_id           = var.api_gateway_vpc_link
  integration_target      = var.alb_shared_listener
}  



##############################################
#
#       API GATEWAY PRIVATE
#
##############################################

resource "aws_api_gateway_base_path_mapping" "this" {
  count       = local.is_private
  api_id        = aws_api_gateway_rest_api.this[count.index].id
  stage_name    = aws_api_gateway_stage.this[count.index].stage_name
  domain_name   = local.full_domain_name
  base_path   = var.base_path

  depends_on = [ 
    aws_api_gateway_rest_api.this,
    aws_api_gateway_stage.this
  ]
}

resource "aws_api_gateway_rest_api" "this" {
  count = local.is_private

  name        = var.app_name
  description = var.app_name

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [var.vpc_endpoint_apigw]
  }

tags               = local.tags
}

resource "aws_api_gateway_rest_api_policy" "this" {

  count = local.is_private

  rest_api_id = aws_api_gateway_rest_api.this[count.index].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action   = "execute-api:Invoke"
        Resource = "${aws_api_gateway_rest_api.this[count.index].execution_arn}/*/*/*"
        Condition = {
          StringEquals = {
            "aws:SourceVpce" = var.vpc_endpoint_apigw
          }
        }
      }
    ]
  })

  depends_on = [
    aws_api_gateway_rest_api.this
  ]
}

#################################
# RESOURCE /{proxy+}
#################################
resource "aws_api_gateway_resource" "this" {
  count       = local.is_private

  depends_on = [
    aws_api_gateway_rest_api.this
  ]
  rest_api_id = aws_api_gateway_rest_api.this[count.index].id
  parent_id   = aws_api_gateway_rest_api.this[count.index].root_resource_id
  path_part   = "{proxy+}"
}

#################################
# METHOD ANY
#################################
resource "aws_api_gateway_method" "this" {

  count         = local.is_private
  rest_api_id   = aws_api_gateway_rest_api.this[count.index].id
  resource_id   = aws_api_gateway_resource.this[count.index].id
  http_method   = "ANY"
  authorization = "NONE"

  depends_on = [
    aws_api_gateway_resource.this
  ]

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

#################################
# INTEGRATION -> ALB via VPC LINK
#################################
resource "aws_api_gateway_integration" "this" {
  count       = local.is_private
  rest_api_id = aws_api_gateway_rest_api.this[count.index].id
  resource_id = aws_api_gateway_resource.this[count.index].id
  http_method = aws_api_gateway_method.this[count.index].http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"

  depends_on = [
    aws_api_gateway_method.this
  ]
  uri                     = "http://${var.alb_shared_dns}:80/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = var.api_gateway_vpc_link
  integration_target      = var.alb_shared_listener

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

#################################
# DEPLOYMENT
#################################
resource "aws_api_gateway_deployment" "this" {
  count = local.is_private

  rest_api_id = aws_api_gateway_rest_api.this[count.index].id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.this[count.index].id,
      aws_api_gateway_method.this[count.index].id,
      aws_api_gateway_integration.this[count.index].id,
      aws_api_gateway_rest_api_policy.this[count.index].id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

#################################
# STAGE + ACCESS LOGS
#################################
resource "aws_api_gateway_stage" "this" {
  count = local.is_private
  rest_api_id   = aws_api_gateway_rest_api.this[count.index].id
  deployment_id = aws_api_gateway_deployment.this[count.index].id
  stage_name    = "default"

  #access_log_settings {
  #  destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  #  format = jsonencode({
  #    requestId        = "$context.requestId"
  #    sourceIp         = "$context.identity.sourceIp"
  #    requestTime      = "$context.requestTime"
  #    httpMethod       = "$context.httpMethod"
  #    resourcePath     = "$context.resourcePath"
  #    status           = "$context.status"
  #   responseLength   = "$context.responseLength"
  #    integrationError = "$context.integration.error"
  #  })
  #}

  depends_on = [
    aws_api_gateway_deployment.this
  ]
} 


resource "aws_ssm_parameter" "this" {
  for_each = { for param in local.ssm_params : param.name => param }

  name        = each.value.name
  description = each.value.description
  type        = each.value.type
  value       = each.value.value
  tags        = local.tags
}

resource "aws_dynamodb_table" "this" {
    for_each = { for t in var.dynamodb_tables : t.table_name => t }

    name         = each.value.table_name
    billing_mode = each.value.billing_mode
    hash_key     = each.value.hash_key
    range_key    = each.value.range_key

    dynamic "attribute" {
        for_each = each.value.attributes
        content {
          name = attribute.value.name
          type = attribute.value.type
        }
    }

    dynamic "global_secondary_index" {
        for_each = each.value.global_secondary_indexes
        content {
          name               = global_secondary_index.value.name
          hash_key           = global_secondary_index.value.hash_key
          range_key          = global_secondary_index.value.range_key
          projection_type    = global_secondary_index.value.projection_type
          non_key_attributes = global_secondary_index.value.non_key_attributes
          read_capacity      = global_secondary_index.value.read_capacity
          write_capacity     = global_secondary_index.value.write_capacity
        }
    }

    tags = local.tags
}

#################################
# S3 BUCKETS
#################################
resource "aws_s3_bucket" "app_buckets" {
  for_each = { for b in local.s3_buckets : b.bucket_name => b }

  bucket        = "${each.value.bucket_name}-${var.environment}"
  force_destroy = lower(tostring(try(each.value.force_destroy, "false"))) == "true"

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "app_buckets" {
  for_each = aws_s3_bucket.app_buckets

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_buckets" {
  for_each = { for k, b in local.s3_buckets : b.bucket_name => b if lower(tostring(try(b.versioning, "true"))) == "true" }

  bucket = aws_s3_bucket.app_buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "app_buckets" {
  for_each = { for k, b in local.s3_buckets : b.bucket_name => b if length(try(b.cors_rules, [])) > 0 }

  bucket = aws_s3_bucket.app_buckets[each.key].id

  dynamic "cors_rule" {
    for_each = each.value.cors_rules
    content {
      allowed_headers = try(cors_rule.value.allowed_headers, ["*"])
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = try(cors_rule.value.expose_headers, [])
      max_age_seconds = try(cors_rule.value.max_age_seconds, 3600)
    }
  }
}




