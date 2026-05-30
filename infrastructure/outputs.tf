output "droplet_ip" {
  value       = digitalocean_droplet.main.ipv4_address
  description = "The public IPv4 address of your main server"
}

output "droplet_urn" {
  value       = digitalocean_droplet.main.urn
  description = "The Uniform Resource Name for the Droplet"
}
