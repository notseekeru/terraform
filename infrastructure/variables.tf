variable "do_token" {
  type        = string
  description = "DigitalOcean API Personal Access Token"
  sensitive   = true
}

variable "ssh_public_keys" {
  type        = map(string)
  description = "Map of SSH public key names to their public key strings for Droplet access"
  sensitive   = true
}

variable "region" {
  type        = string
  default     = "sgp1"
  description = "DigitalOcean region data center"
}

variable "droplet_size" {
  type        = string
  default     = "s-1vcpu-1gb"
  description = "Droplet hardware size (slug)"
}
