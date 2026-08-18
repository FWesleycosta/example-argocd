################################ fibra-risco-credito-dev ##################################

data "aws_s3_bucket" "s3" {
  bucket = var.NAME_BUCKET_FRONT
}

# Este data source AGORA usará o provider "virginia" (us-east-1)
data "aws_acm_certificate" "acm_certificate" {
  provider    = aws.virginia 
  domain      = "*.bancofibra.com.br"
  statuses    = ["ISSUED"]
  most_recent = true
}


resource "aws_cloudfront_response_headers_policy" "cors_policy" {
  name    = "cors-policy-${var.NAME_BUCKET_FRONT}"
  comment = "CORS headers for ${var.APP_NAME}-${var.ENVIRONMENT}"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["Authorization", "Content-Type", "Origin", "Accept", "X-Requested-With"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    access_control_max_age_sec = 3600

    origin_override = true
  }
}

resource "aws_cloudfront_origin_access_control" "cloudfront_oac" {
  name                              = "oac-${var.NAME_BUCKET_FRONT}"
  description                       = "OAC for ${var.NAME_BUCKET_FRONT}.bancofibra.com.br"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  origin {
    domain_name              = data.aws_s3_bucket.s3.bucket_regional_domain_name
    origin_id                = var.NAME_BUCKET_FRONT
    origin_access_control_id = aws_cloudfront_origin_access_control.cloudfront_oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.domain_name
  aliases             = [local.domain_name]
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.NAME_BUCKET_FRONT
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 1
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true

    forwarded_values {
      query_string = false
      headers = [ "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers" ]
      cookies {
        forward = "none"
      }
    }
  }


  ordered_cache_behavior {
    path_pattern           = "*.js"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.NAME_BUCKET_FRONT
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 1
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true

    response_headers_policy_id = aws_cloudfront_response_headers_policy.cors_policy.id

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]
      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code = 403
    response_code = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.acm_certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    project = ""
  }
}

data "aws_iam_policy_document" "iam_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.s3.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cloudfront_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = data.aws_s3_bucket.s3.id
  policy = data.aws_iam_policy_document.iam_policy.json
}
 
