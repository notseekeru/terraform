terraform {
  required_version = ">= 1.0"

  # Uses Cloudflare R2 as S3-compatible remote backend
  backend "s3" {
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
