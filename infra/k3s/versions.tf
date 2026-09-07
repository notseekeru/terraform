terraform {
  required_version = ">= 1.0"

  # All backend config (bucket/key/region/endpoint/skip_*/use_lockfile) is
  # supplied at init from infra/k3s/backend.tfbackend.tpl (see Makefile).
  backend "s3" {}

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
