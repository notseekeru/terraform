output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_dist.domain_name
}

output "alb_domain_validation_cname" {
  description = "CNAME to add in Cloudflare to validate the ACM HTTPS certificate (empty if no domain set)"
  value = var.alb_domain != "" ? [
    for r in aws_acm_certificate.alb[0].domain_validation_options : {
      name  = r.resource_record_name
      type  = r.resource_record_type
      value = r.resource_record_value
    }
  ] : []
}
