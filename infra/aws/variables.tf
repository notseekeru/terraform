variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t4g.micro" # ARM-based, better performance/watt
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "POSTGRES_PASSWORD" {
  type      = string
  sensitive = true
}

variable "ALERT_EMAIL" {
  type      = string
  sensitive = true
  # Injected via infisical secret ALERT_EMAIL (TF_VAR_ALERT_EMAIL)
}

variable "credit_cap_usd" {
  type    = number
  default = 190.0
  # Free-tier promotional credit balance (~$100 + $100 explore); alarm before exhaustion
}

variable "alb_domain" {
  type    = string
  default = ""
  # Custom domain (e.g. app.example.tech) for ACM HTTPS on the ALB.
  # Empty => ALB stays HTTP:80 only; DNS is managed in Cloudflare,
  # so supply the value at apply time via -var or TF_VAR_alb_domain.
}
