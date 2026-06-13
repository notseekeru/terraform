# Create and register SSH keys
resource "digitalocean_ssh_key" "vm_key" {
  for_each   = var.ssh_public_keys
  name       = each.key
  public_key = each.value
}

resource "digitalocean_droplet" "main" {
  image    = "debian-13-x64"
  name     = "vm-main-server"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [for k in digitalocean_ssh_key.vm_key : k.id]

  tags = ["vm", "main-server"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventories/droplets.ini"
  content = templatefile("${path.module}/inventory.tmpl", {
    droplet_ip = digitalocean_droplet.main.ipv4_address
  })
  depends_on = [
    digitalocean_droplet.main
  ]
}