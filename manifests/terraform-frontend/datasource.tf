# Certificado wildcard em us-east-1 (obrigatório para CloudFront). Só consultado quando
# cloudfront_enabled e acm_certificate_arn não foi informado.
data "aws_acm_certificate" "this" {
  count    = local.lookup_cert
  provider = aws.us_east_1

  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

# Policy do bucket: leitura pelo CloudFront (OAC, restrita à distribuição) + deny sem TLS.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = local.cloudfront_enabled ? [1] : []
    content {
      sid       = "AllowCloudFrontOAC"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.site.arn}/*"]
      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = [module.cloudfront[0].ARN]
      }
    }
  }
}
