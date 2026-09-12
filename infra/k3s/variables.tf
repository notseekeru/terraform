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
variable "MAXTERVIEW_LLM_BASE_URL" {
  description = "OpenAI-compatible base URL for prod (e.g. https://api.deepseek.com/v1)"
  sensitive   = true
}

variable "MAXTERVIEW_LLM_MODEL" {
  description = "Model id used as interviewer + feedback formatter"
  sensitive   = true
}

variable "MAXTERVIEW_LLM_API_KEY" {
  description = "API key for the LLM provider; empty is correct for an unauthenticated self-hosted endpoint"
  sensitive   = true
  default     = ""
}

# Billing is optional at runtime: unset keys make /billing/* answer 503, nothing else breaks.
variable "MAXTERVIEW_STRIPE_SECRET_KEY" {
  description = "Stripe secret key (prod or test mode)"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_STRIPE_WEBHOOK_SECRET" {
  description = "Stripe webhook signing secret for the /api/billing/webhook endpoint"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_STRIPE_PRICE_ID" {
  description = "Stripe price id for the premium monthly plan"
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
