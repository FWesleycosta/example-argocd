variable "NAME_BUCKET_FRONT" {
    description = "Identificador único e multiuso da aplicação. Este valor é utilizado como nome do bucket S3 onde ficará o index do front, origin_id do CloudFront, identificação e comentário da distribuição, subdomínio (antes de .bancofibra.com.br), nome lógico dos recursos."
    type        = string
}

variable "AWS_REGION" {
  type        = string
}

variable "APP_NAME" {
  type = string
}

variable "ENVIRONMENT" {
  type = string
}
