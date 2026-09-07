terraform {
  required_version = ">= 1.0"

  # All backend config (bucket/key/region/endpoint/skip_*/use_lockfile) is
  # supplied at init from infra/cloudflare/backend.tfbackend.tpl (see Makefile).
  backend "s3" {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
