terraform {
  required_version = ">= 1.11"

  # Uses Cloudflare R2 as S3-compatible remote backend. bucket/key/region and the
  # skip_* flags are fixed here; only the R2 creds and endpoints.s3 pass as
  # -backend-config flags, because they cannot live in a committed file.
  backend "s3" {
    bucket = "terraform-state"
    key    = "terraform/k3s/terraform.tfstate"
    region = "auto"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    # S3-native lockfile locking (guards concurrent applies per module).
    use_lockfile = true
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }
  }
}
