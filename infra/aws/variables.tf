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

variable "ALB_DOMAIN" {
  type    = string
  default = ""
  # Custom domain (e.g. alb.seekeru.tech) for ACM HTTPS on the ALB.
  # Empty => ALB stays HTTP:80 only and no DNS record is managed.
  # When set: infra/aws creates its own Cloudflare records (see compute.tf)
  # pointing at the ALB and auto-issuing the ACM cert via the validation CNAME.
}

variable "CLOUDFLARE_API_TOKEN" {
  type      = string
  sensitive = true
  # Injected via infisical TF_VAR_CLOUDFLARE_API_TOKEN (same as infra/cloudflare).
}

variable "cloudflare_zone_id" {
  type    = string
  default = "5a1a5f826d5a3398dc78ba360e24dfa0" # seekeru.tech
}

