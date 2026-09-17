# Same names as infra/k3s on purpose: the Infisical `staging` environment inherits the shared
# values from `prod` and overrides only the env-specific ones, so every key here is a value an
# operator already knows. Declared locally because this is a separate root module/state.

variable "MAXTERVIEW_DATABASE_URL" {
  description = "Staging Neon direct-host DSN (sslmode=require, NOT the -pooler host, NOT the prod project)"
  sensitive   = true

  validation {
    condition     = length(trimspace(var.MAXTERVIEW_DATABASE_URL)) > 0 && strcontains(var.MAXTERVIEW_DATABASE_URL, "sslmode=require")
    error_message = "DATABASE_URL must be the staging Neon DSN and carry sslmode=require."
  }

  # The inherited-from-`prod` value is the prod DSN: without this guard, `ENV=staging` with an
  # unset override would silently point staging pods at the production database.
  validation {
    condition     = !strcontains(var.MAXTERVIEW_DATABASE_URL, "ep-tiny-hall-b3e0wb3g")
    error_message = "Refusing the prod Neon endpoint (ep-tiny-hall-b3e0wb3g): override TF_VAR_MAXTERVIEW_DATABASE_URL in the Infisical `staging` environment with the staging project's DSN."
  }
}

variable "MAXTERVIEW_MIGRATE_DATABASE_URL" {
  description = "Migrate-role staging DSN; empty falls back to DATABASE_URL in the PreSync Job"
  sensitive   = true
  default     = ""
}

variable "GITHUB_USERNAME" {
  description = "GitHub username for GHCR authentication"
  sensitive   = false
  default     = "notseekeru"
}

variable "GITHUB_PAT" {
  description = "GitHub PAT with read:packages, for the namespace-local ghcr-login pull secret"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_DOMAIN" {
  description = "Clerk instance domain for staging (the DEVELOPMENT instance, not clerk.seekeru.tech)"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_JWKS_URL" {
  description = "JWKS URL of the same staging Clerk instance"
  sensitive   = true
}

variable "MAXTERVIEW_CLERK_AUDIENCE" {
  description = "Optional Clerk JWT audience; empty accepts tokens without an aud claim"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_LLM_BASE_URL" {
  description = "OpenAI-compatible base URL (inherits the prod qwen endpoint unless overridden)"
  sensitive   = true

  validation {
    condition     = length(trimspace(var.MAXTERVIEW_LLM_BASE_URL)) > 0
    error_message = "LLM_BASE_URL must not be empty: an empty value silently boots the backend in STUB_MODE."
  }
}

variable "MAXTERVIEW_LLM_MODEL" {
  description = "Model id used as interviewer + feedback formatter"
  sensitive   = true

  validation {
    condition     = length(trimspace(var.MAXTERVIEW_LLM_MODEL)) > 0
    error_message = "LLM_MODEL must not be empty: an empty value silently boots the backend in STUB_MODE."
  }
}

variable "MAXTERVIEW_LLM_API_KEY" {
  description = "Empty is correct for an unauthenticated self-hosted endpoint"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_BYOK_ENCRYPTION_KEY" {
  description = "Fernet key for BYOK; inherits prod's unless staging should hold unreadable-in-prod rows"
  sensitive   = true
}

# Test-mode keys by design: staging must never move real money. Leaving them empty is allowed
# (staging simply 503s /api/billing/* like any unconfigured env) — the point is that a real key
# here would be a mistake, so the default is "billing dark".
variable "MAXTERVIEW_PAYMONGO_SECRET_KEY" {
  description = "PayMongo TEST secret key (sk_test_...) for the staging webhook endpoint"
  sensitive   = true
  default     = ""
}

variable "MAXTERVIEW_PAYMONGO_WEBHOOK_SECRET" {
  description = "Signing secret of the TEST webhook endpoint registered for the staging URL"
  sensitive   = true
  default     = ""
}
