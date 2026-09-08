terraform {
  required_version = ">= 1.0"

  # Uses Cloudflare R2 as S3-compatible remote backend. The structural skip_*/
  # use_lockfile settings live in the static backend block below; the R2 bucket/key/
  # region/access_key/secret_key reach it at init as -backend-config in the Makefile
  # (secrets expand from infisical-injected TF_VAR_R2_*), and the R2 endpoint comes
  # from the ambient AWS_ENDPOINT_URL_S3 env var.
  backend "s3" {
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    # S3-native lockfile locking (guards concurrent applies per module).
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
