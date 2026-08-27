resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = { Name = "main-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier             = "main-db"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16"
  username               = "admin"
  password               = var.POSTGRES_PASSWORD
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = false # Single-AZ for Free Tier
  publicly_accessible    = false
}
