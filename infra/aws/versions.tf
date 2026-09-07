terraform {
  required_version = ">= 1.0"

  # Uses Cloudflare R2 as S3-compatible remote backend. All backend config
  # (bucket/key/region/endpoint/skip_*/use_lockfile) is supplied at init from
  # infra/aws/backend.tfbackend.tpl via scripts/render-tfbackend.sh (see Makefile).
  backend "s3" {}

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
