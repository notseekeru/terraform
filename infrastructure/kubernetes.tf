data "digitalocean_kubernetes_versions" "stable" {
  version_prefix = "1.32." # Check the latest stable version via `doctl kubernetes options versions`
}

resource "digitalocean_kubernetes_cluster" "lab_cluster" {
  name    = "lab-cluster-01"
  region  = var.default_region
  version = data.digitalocean_kubernetes_versions.stable.latest_version

  node_pool {
    name       = "worker-pool"
    size       = var.default_size
    node_count = 3
  }
}

# 2. The Firewall
resource "digitalocean_firewall" "k8s_firewall" {
  name = "k8s-firewall"

  # Use the tag automatically assigned to K8s nodes by DigitalOcean
  tags = ["k8s:${digitalocean_kubernetes_cluster.lab_cluster.id}"]

  # Allow Inbound traffic for your ingress
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0"]
  }

  # Allow outbound traffic (required for K8s nodes to pull images/updates)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0"]
  }
}

# 3. Output the kubeconfig so you can actually use the cluster
resource "local_file" "kubeconfig" {
  filename = "${path.module}/../kubeconfig"
  content  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.raw_config
}