# 1. SSM Parameter for DB Password
resource "aws_ssm_parameter" "POSTGRES_PASSWORD" {
  name  = "/app/POSTGRES_PASSWORD"
  type  = "SecureString"
  value = var.POSTGRES_PASSWORD
}

# 2. SSM Parameter for DB Endpoint (for EC2 injection)
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/app/db_endpoint"
  type  = "String"
  value = aws_db_instance.main.address
}
