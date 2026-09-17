terraform {
  required_version = ">= 1.0"

  # Same R2 remote backend as infra/k3s, but its OWN state key (the Makefile builds the key from
  # MOD, so `MOD=k3s-staging` => `terraform/k3s-staging/terraform.tfstate`). That separation is the
  # whole point of this module: the prod module owns the cluster (argocd, ingress-nginx, the
  # `maxterview` namespace), and letting a staging apply share its state would put the two
  # environments' lifecycles in one plan.
  backend "s3" {
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    use_lockfile                = true
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}
