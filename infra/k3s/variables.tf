variable "CLOUDFLARE_TOKEN" {
  description = "Cloudflare Tunnel token for cloudflared"
  sensitive   = true
}

variable "GITHUB_USERNAME" {
  description = "GitHub username for GHCR authentication"
  sensitive   = false
  default     = "notseekeru"
}

variable "GITHUB_PAT" {
  description = "GitHub Personal Access Token (repo + read:packages scopes)"
  sensitive   = true
}

variable "GITHUB_REPO_URL" {
  description = "GitOps repository URL"
  sensitive   = false
  default     = "https://github.com/notseekeru/gitops.git"
}

variable "DIAGRAM_API_KEY" {
  description = "API key for the diagram service"
  sensitive   = true
}

variable "POSTGRES_PASSWORD" {
  description = "Password for the local PostgreSQL database"
  sensitive   = true
}

# --- maxterview ---
# Every value below lands in `maxterview-secrets` under a key that IS the env var name; the backend
# Deployment injects the whole secret with `envFrom`, so names are a contract (see that manifest).

variable "MAXTERVIEW_DATABASE_URL" {
  description = "Neon direct-host DSN (sslmode=require, NOT the -pooler host) for the maxterview backend"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_JWKS_URL" {
  description = "Clerk production instance JWKS URL (backend verifies JWTs against it)"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_DOMAIN" {
  description = "Clerk production instance domain, e.g. https://clerk.seekeru.tech"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_AUDIENCE" {
  description = "Optional Clerk JWT audience; empty accepts tokens without an aud claim"
  sensitive   = true
  default     = ""
}

# Required on purpose: empty LLM_* silently boots the backend in STUB mode (no model calls),
# which looks like a healthy deploy while every interview is fake. Fail at plan time instead.
# The `validation` blocks are load-bearing: a *set but empty* TF_VAR (Infisical holds an empty
# key) satisfies "required", so without them an empty value wipes the live LLM_* and stubs prod.
variable "MAXTERVIEW_LLM_BASE_URL" {
  description = "OpenAI-compatible base URL for prod (e.g. https://api.deepseek.com/v1)"
  sensitive   = true

  validation {
    condition     = length(trimspace(var.MAXTERVIEW_LLM_BASE_URL)) > 0
    error_message = "LLM_BASE_URL must not be empty: an empty value silently boots the backend in STUB_MODE (fake interviews)."
  }
}

variable "MAXTERVIEW_LLM_MODEL" {
  description = "Model id used as interviewer + feedback formatter"
  sensitive   = true

  validation {
    condition     = length(trimspace(var.MAXTERVIEW_LLM_MODEL)) > 0
    error_message = "LLM_MODEL must not be empty: an empty value silently boots the backend in STUB_MODE (fake interviews)."
  }
}

variable "MAXTERVIEW_LLM_API_KEY" {
  description = "API key for the LLM provider; empty is correct for an unauthenticated self-hosted endpoint"
  sensitive   = true
  default     = ""
}

# BYOK (app/byok.py): encrypts owner-supplied provider keys at rest. Required rather than optional
# so a deploy cannot silently ship the settings card read-only. Durable by nature: rotating it
# orphans every saved row (they degrade to the system LLM_* provider until re-saved), the app
# itself boots either way.
variable "MAXTERVIEW_BYOK_ENCRYPTION_KEY" {
  description = "Fernet key encrypting per-owner BYOK provider keys (see BYOK.md)"
  sensitive   = true
}

# Billing is optional at runtime: unset keys make /api/billing/* answer 503, nothing else breaks.
# Period mode (the shipping rail) needs only these two; `PAYMONGO_PLAN_ID` is subscription-mode only.
variable "MAXTERVIEW_PAYMONGO_SECRET_KEY" {
  description = "PayMongo secret key (sk_test_/sk_live_); empty => /api/billing/* 503s"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_PAYMONGO_WEBHOOK_SECRET" {
  description = "Signing secret of the PayMongo webhook endpoint registered for /api/billing/webhook"
  sensitive   = true
  default     = ""
}

# Reserved (D12): the migrate-role DSN read only by the in-cluster migration Job. Unset = falls
# back to DATABASE_URL. Not consumed by app code yet.
variable "MAXTERVIEW_MIGRATE_DATABASE_URL" {
  description = "Migrate-role Neon DSN for the in-cluster migration Job; empty falls back to DATABASE_URL"
  sensitive   = true
  default     = ""
}

variable "app_yaml_path" {
  type        = string
  default     = null
  description = "Path to app.yaml manifest. Defaults to ../../../gitops/app.yaml relative to this module."
}

# --- maxterview logs (Alloy -> Grafana Cloud Loki) ---
# `maxterview-logs`, consumed by the Alloy Deployment with `valueFrom`: the keys are the env-var
# names the Alloy config reads via sys.env().

variable "MAXTERVIEW_LOKI_URL" {
  description = "Grafana Cloud Loki push URL: https://logs-prod-<region>.grafana.net/loki/api/v1/push"
  sensitive   = true
}

variable "MAXTERVIEW_LOKI_USER" {
  description = "Grafana Cloud stack instance ID, used as the Loki basic-auth username"
  sensitive   = true
}

variable "MAXTERVIEW_LOKI_TOKEN" {
  description = "Grafana Cloud access-policy token scoped logs:write (Alloy's only credential)"
  sensitive   = true
}
