resource "digitalocean_ssh_key" "this" {
  name       = "default"
  public_key = var.SSH_PUBLIC_KEY
}

locals {
  all_ssh_key_ids = [digitalocean_ssh_key.this.id]
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
  filename  = "${path.module}/../../../ansible/inventories/droplets.ini"
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
