terraform {
  required_version = ">= 1.0"

  # Uses Cloudflare R2 as S3-compatible remote backend
  backend "s3" {
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    # S3-native lockfile locking (guards concurrent applies per module).
    # NB: relies on R2 supporting conditional PutObject + strong consistency.
    # Trust via the -lock-timeout negative test before treating as authoritative.
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
