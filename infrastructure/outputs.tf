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
