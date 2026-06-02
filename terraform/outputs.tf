output "cloudfront_url" {
  value = aws_cloudfront_distribution.meditrack_cdn.domain_name
}