# Create and register your SSH key
resource "digitalocean_ssh_key" "vm_key" {
  name       = "vm-ssh-key"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "main" {
  image    = "debian-13-x64"
  name     = "vm-main-server"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [digitalocean_ssh_key.vm_key.id]

  tags = ["vm", "main-server"]
}

resource "local_file" "ansible_inventory" {
    filename = "${path.module}/../ansible/inventories/droplets.ini"
    content  = templatefile("${path.module}/inventory.tmpl", {
      droplet_ip = digitalocean_droplet.main.ipv4_address
    })
}