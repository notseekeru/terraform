variable "DO_TOKEN" {
  type      = string
  sensitive = true
}

variable "SSH_PUBLIC_KEY" {
  type      = string
  sensitive = true
}

variable "default_region" {
  type    = string
  default = "sgp1"
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
  default = {}
}
