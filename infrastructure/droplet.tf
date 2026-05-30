resource "digitalocean_droplet" "proxy_node" {
    image    = "ubuntu-24-04-x64"
    name     = "proxy-node-01"
    region   = "sgp1" # Choose your closest region
    size     = "s-1vcpu-1gb"

    # Inject your SSH Key ID (Get ID from DO dashboard or 'doctl compute ssh-key
list')
    ssh_keys = [var.ssh_key_id]

    tags = ["env:production", "type:proxy"]
}

variable "ssh_key_id" {
    description = "The ID of the SSH key to add to the droplet"
    type        = string
}