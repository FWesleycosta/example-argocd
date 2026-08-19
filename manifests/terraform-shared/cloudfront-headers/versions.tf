terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Backend informado no init (uma vez por conta):
#   terraform init -backend-config="bucket=tfstate-platform-<env>" \
#                  -backend-config="key=cloudfront-headers/terraform.tfstate" \
#                  -backend-config="region=<região>" -backend-config="encrypt=true"
terraform {
  backend "s3" {}
}
