#################################
# S3 — bucket do site (privado; servido pelo CloudFront via OAC)
#################################
resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "site" {
  count = var.access_logging_bucket != "" ? 1 : 0

  bucket        = aws_s3_bucket.site.id
  target_bucket = var.access_logging_bucket
  target_prefix = "s3/${var.bucket_name}/"
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

#################################
# CloudFront (opcional: cloudfront_enabled) — módulo reutilizável do Fibra.DevOps.Terraform
#################################
module "cloudfront" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_cloudfront_distribution"
  count  = local.cf_count

  name                 = var.bucket_name
  origin_domain_name   = aws_s3_bucket.site.bucket_regional_domain_name
  aliases              = [local.domain_name]
  acm_certificate_arn  = local.certificate_arn
  price_class          = var.price_class
  cors_allowed_origins = var.cors_allowed_origins
  # defaults do módulo: OAC, CachingOptimized + CORS-S3Origin, http2and3, security headers,
  # fallback SPA 403/404 → /index.html, TLSv1.2_2021
  tags = local.tags
}
