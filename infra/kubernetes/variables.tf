variable "do_token" {
  type      = string
  sensitive = true
}

variable "default_region" {
  type    = string
  default = "sgp1"
}

variable "cloudflare_tunnel_token" {
  sensitive = true
}

variable "github_username" {
  sensitive = false
}

variable "github_pat" {
  description = "GitHub Personal Access Token (with repo and read:packages scopes)"
  sensitive   = true
}

variable "gitops_repo_url" {
  sensitive = false
}

variable "diagram_api_key" {
  sensitive = true
}
