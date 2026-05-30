variable "do_token" {
  type        = string
  description = "DigitalOcean API Personal Access Token"
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "The public SSH key string for Droplet access"
  sensitive   = true
}

variable "region" {
  type        = string
  default     = "sgp1"
  description = "DigitalOcean region data center"
}

variable "droplet_size" {
  type        = string
  default     = "s-1vcpu-1gb-10gb"
  description = "Droplet hardware size (slug)"
}
