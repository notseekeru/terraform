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

variable "app_yaml_path" {
  type        = string
  default     = null
  description = "Path to app.yaml manifest. Defaults to ../../../gitops/app.yaml relative to this module."
}
