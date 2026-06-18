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
  filename = pathexpand("~/kubeconfig")
  content  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.raw_config
}

provider "helm" {
  kubernetes = {
    host                   = digitalocean_kubernetes_cluster.lab_cluster.endpoint
    token                  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  depends_on       = [digitalocean_kubernetes_cluster.lab_cluster]
}