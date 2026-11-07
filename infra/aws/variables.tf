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
  default = "t4g.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_engine_version" {
  type    = string
  default = "18.6"
}

variable "domain" {
  type    = string
  default = "sesume.seekeru.tech"
}

variable "cloudflare_zone_id" {
  type    = string
  default = "5a1a5f826d5a3398dc78ba360e24dfa0"
}

# Empty until the lambda image exists in ECR. The first apply creates the repository only,
# the push fills it, the second apply creates the functions.
variable "lambda_image_uri" {
  type    = string
  default = ""
}

variable "github_repo" {
  type    = string
  default = "notseekeru/sesume"
}

# GitHub issues the subject claim with the numeric owner and repository IDs, so a trust policy
# written against repo:owner/name alone stops matching. Both forms are listed.
variable "github_repo_immutable" {
  type    = string
  default = "notseekeru@124259804/sesume@1441552332"
}

variable "POSTGRES_PASSWORD" {
  type      = string
  sensitive = true
}

variable "AUTH_SECRET" {
  type      = string
  sensitive = true
}

variable "DATA_KEY" {
  type      = string
  sensitive = true
}

variable "ORIGIN_TOKEN" {
  type      = string
  sensitive = true
}

variable "ALERT_EMAIL" {
  type      = string
  sensitive = true
}

variable "credit_cap_usd" {
  type    = number
  default = 190.0
}

variable "CLOUDFLARE_API_TOKEN" {
  type      = string
  sensitive = true
}

variable "CLOUDFLARE_ACCOUNT_ID" {
  type      = string
  sensitive = true
}
