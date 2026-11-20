terraform {
  required_version = ">= 1.11"

  # Uses Cloudflare R2 as S3-compatible remote backend. bucket/key/region and the
  # skip_* flags are fixed here; only the values that cannot live in a committed
  # file reach init as -backend-config flags from the Makefile: the R2 creds and
  # endpoints.s3, both from infisical-injected TF_VAR_R2_*.
  backend "s3" {
    bucket = "terraform-state"
    key    = "terraform/aws/terraform.tfstate"
    region = "auto"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    # S3-native lockfile locking (guards concurrent applies per module).
    use_lockfile = true
  }

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
