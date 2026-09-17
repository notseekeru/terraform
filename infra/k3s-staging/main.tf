# Staging env-scoped resources: the namespace + the Secret the staging Deployment consumes with
# `envFrom` (D11/D13 — one cluster, one namespace per durable env, staging on its own Neon project).
#
# Run with: make plan MOD=k3s-staging ENV=staging && make apply MOD=k3s-staging ENV=staging
# `ENV=staging` selects the Infisical environment, which inherits every shared value from `prod`
# (R2 backend creds, Cloudflare token, the LLM/qwen pair, the BYOK key) and overrides only what
# differs — the Neon DSN, the Clerk instance and the PayMongo keys. Same TF_VAR names as prod on
# purpose: no new keys to learn, and nothing here can read prod's DSN by accident.
#
# Only the two env-scoped objects live here. The cluster itself (argocd, ingress-nginx, the
# `maxterview` namespace) belongs to infra/k3s and must never be recreated from this module.

resource "kubernetes_namespace" "staging" {
  metadata {
    name = "maxterview-staging"
  }
}

resource "kubernetes_secret" "staging_secrets" {
  metadata {
    name      = "maxterview-staging-secrets"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }
  # Keys are the app's env var names verbatim (UPPERCASE only) — `envFrom` is all-or-nothing.
  data = {
    DATABASE_URL            = var.MAXTERVIEW_DATABASE_URL
    MIGRATE_DATABASE_URL    = var.MAXTERVIEW_MIGRATE_DATABASE_URL
    CLERK_JWKS_URL          = var.MAXTERVIEW_CLERK_JWKS_URL
    CLERK_DOMAIN            = var.MAXTERVIEW_CLERK_DOMAIN
    CLERK_AUDIENCE          = var.MAXTERVIEW_CLERK_AUDIENCE
    LLM_BASE_URL            = var.MAXTERVIEW_LLM_BASE_URL
    LLM_MODEL               = var.MAXTERVIEW_LLM_MODEL
    LLM_API_KEY             = var.MAXTERVIEW_LLM_API_KEY
    BYOK_ENCRYPTION_KEY     = var.MAXTERVIEW_BYOK_ENCRYPTION_KEY
    PAYMONGO_SECRET_KEY     = var.MAXTERVIEW_PAYMONGO_SECRET_KEY
    PAYMONGO_WEBHOOK_SECRET = var.MAXTERVIEW_PAYMONGO_WEBHOOK_SECRET
  }
  type = "Opaque"
}
