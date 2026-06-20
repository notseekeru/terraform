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

resource "digitalocean_ssh_key" "this" {
  for_each   = var.ssh_public_keys
  name       = each.key
  public_key = each.value
}

locals {
  all_ssh_key_ids = [for k in digitalocean_ssh_key.this : k.id]
}

resource "digitalocean_droplet" "this" {
  for_each = var.servers

  image    = coalesce(each.value.image, var.default_image)
  name     = each.key
  region   = coalesce(each.value.region, var.default_region)
  size     = coalesce(each.value.size, var.default_size)
  ssh_keys = local.all_ssh_key_ids

  tags = distinct(concat(["vm"], each.value.tags != null ? each.value.tags : []))

  lifecycle {
    create_before_destroy = true
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventories/droplets.ini"
  content = templatefile("${path.module}/inventory.tmpl", {
    servers = {
      for k, d in digitalocean_droplet.this : k => {
        ipv4_address = d.ipv4_address
        tags         = d.tags
        region       = d.region
        size         = d.size
        image        = d.image
      }
    }
  })
  depends_on = [
    digitalocean_droplet.this
  ]
}

output "droplets" {
  value = {
    for k, d in digitalocean_droplet.this : k => {
      ipv4_address = d.ipv4_address
      ipv6_address = d.ipv6_address
      urn          = d.urn
      region       = d.region
      size         = d.size
      image        = d.image
      tags         = d.tags
    }
  }
}

output "droplet_ips" {
  value       = { for k, d in digitalocean_droplet.this : k => d.ipv4_address }
  description = "Map of server name → public IPv4 address"
}
