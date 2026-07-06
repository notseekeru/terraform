provider "digitalocean" {
  token = var.do_token
}

provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.lab_cluster.endpoint
    token                  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.lab_cluster.endpoint
  token                  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.cluster_ca_certificate)
}

provider "kubectl" {
  host                   = digitalocean_kubernetes_cluster.lab_cluster.endpoint
  token                  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}
