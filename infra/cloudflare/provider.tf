# Declarative Cloudflare config. Requires an API token scoped to
# Zone:DNS:Edit + Zone:Read on the zones below, injected at apply time via
# infisical as TF_VAR_CLOUDFLARE_API_TOKEN (never stored in repo).
provider "cloudflare" {
  api_token = var.CLOUDFLARE_API_TOKEN
}
