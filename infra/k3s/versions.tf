terraform {
  required_version = ">= 1.11"

  # State lives in Postgres (Neon) through the pg backend. PG_CONN_STR and this
  # module's PG_SCHEMA_NAME come from the environment.
  backend "pg" {}

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
