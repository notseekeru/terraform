output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_dist.domain_name
}
