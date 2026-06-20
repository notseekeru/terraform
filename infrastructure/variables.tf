variable "do_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel token for cloudflared"
  sensitive   = true
}

variable "github_username" {
  description = "GitHub username"
  sensitive   = false
}

variable "github_pat" {
  description = "GitHub Personal Access Token (with repo and read:packages scopes)"
  sensitive   = true
}

variable "gitops_repo_url" {
  description = "URL of your GitOps repository (e.g., https://github.com/notseekeru/gitops.git)"
  sensitive   = false
}