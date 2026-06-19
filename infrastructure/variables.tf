variable "do_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_keys" {
  type = map(string)
}

variable "default_region" {
  type        = string
  default     = "sgp1"
  description = "Default DigitalOcean region for servers that don't specify one"
}

variable "default_size" {
  type    = string
  default = "s-1vcpu-1gb"
}

variable "default_image" {
  type    = string
  default = "debian-13-x64"
}

variable "servers" {
  type = map(object({
    image  = optional(string)
    region = optional(string)
    size   = optional(string)
    tags   = optional(list(string))
  }))

  default = {
    # N/A
  }
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