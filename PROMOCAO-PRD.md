╷
│ Error: creating S3 Bucket (fibra-boletador-dev): operation error S3: CreateBucket, https response error StatusCode: 409, RequestID: KC5SNT2J615JBNF0, HostID: zu5VllUtzjb121XjYmbNgG9qNIuHrXEioBPI0Qt9k3XmbRJOV6XufPcJmcqecbe7IngzVVUwdPHtGHMdeZVf8XuNFyM0Ar1a, BucketAlreadyOwnedByYou: Your previous request to create the named bucket succeeded and you already own it.
│ 
│   with aws_s3_bucket.site,
│   on main.tf line 4, in resource "aws_s3_bucket" "site":
│    4: resource "aws_s3_bucket" "site" {
│ 
╵
╷
│ Error: creating CloudFront Origin Access Control (oac-fibra-boletador-dev): operation error CloudFront: CreateOriginAccessControl, https response error StatusCode: 409, RequestID: a00be7ec-234e-4f72-9053-e7e303ce50d0, OriginAccessControlAlreadyExists: An origin access control with the same name already exists.
│ 
│   with module.cloudfront[0].aws_cloudfront_origin_access_control.this[0],
│   on .terraform/modules/cloudfront/modules/aws_cloudfront_distribution/main.tf line 1, in resource "aws_cloudfront_origin_access_control" "this":
│    1: resource "aws_cloudfront_origin_access_control" "this" {
