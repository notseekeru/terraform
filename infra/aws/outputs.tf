output "app_url" {
  value = "https://${var.domain}"
}

output "api_function_url" {
  value = try(aws_lambda_function_url.api["api"].function_url, "")
}

output "ecr_repository_url" {
  value = aws_ecr_repository.lambda.repository_url
}

output "edge_ip" {
  value = aws_eip.edge.public_ip
}

output "database_endpoint" {
  value = aws_db_instance.main.address
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.sesume.id
}
