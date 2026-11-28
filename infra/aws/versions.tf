terraform {
  required_version = ">= 1.11"

  # State lives in Postgres (Neon) through the pg backend. PG_CONN_STR and this
  # module's PG_SCHEMA_NAME come from the environment.
  backend "pg" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
