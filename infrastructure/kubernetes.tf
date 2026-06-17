resource "digitalocean_kubernetes_cluster" "lab_cluster" {
  name     = "lab-cluster"
  region   = var.default_region
  version  = "1.34.8-do.1"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
}

resource "local_file" "kubeconfig" {
  filename = "~/kubeconfig"
  content  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.raw_config
}