variable "DO_TOKEN" {
  type      = string
  sensitive = true
}

variable "default_region" {
  type    = string
  default = "sgp1"
}

variable "CLOUDFLARE_TOKEN" {
  sensitive = true
}

variable "GITHUB_USERNAME" {
  sensitive = false
}

variable "GITHUB_PAT" {
  description = "GitHub Personal Access Token (with repo and read:packages scopes)"
  sensitive   = true
}

variable "GITHUB_REPO_URL" {
  sensitive = false
}

variable "app_yaml_path" {
  type    = string
  default = null
  description = "Path to app.yaml manifest. Defaults to ../../../gitops/app.yaml relative to this module."
}

variable "DIAGRAM_API_KEY" {
  sensitive = true
}
