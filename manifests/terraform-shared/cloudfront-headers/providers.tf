# CloudFront é global; qualquer região serve para a API. Mantemos a região do ambiente por
# consistência com as service connections.
provider "aws" {
  region = var.aws_region
}
