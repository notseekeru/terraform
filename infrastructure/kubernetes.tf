# --- Infrastructure ---

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

# --- Providers ---

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

# --- ArgoCD Installation ---

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"                       # Pin a stable version
  depends_on       = [digitalocean_kubernetes_cluster.lab_cluster]
}

# --- Secrets (created before ArgoCD syncs) ---

# 1. Cloudflare Tunnel Token (for cloudflared pod)
resource "kubernetes_secret" "cloudflare_tunnel_token" {
  depends_on = [digitalocean_kubernetes_cluster.lab_cluster]

  metadata {
    name      = "cloudflared-token"
    namespace = "default"
  }
  data = {
    token = var.cloudflare_tunnel_token           # Provide this variable securely
  }
  type = "Opaque"
}

# 2. GitHub Container Registry credentials (for pulling images)
resource "kubernetes_secret" "ghcr_credentials" {
  depends_on = [digitalocean_kubernetes_cluster.lab_cluster]

  metadata {
    name      = "ghcr-login"
    namespace = "default"
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_pat
          auth     = base64encode("${var.github_username}:${var.github_pat}")
        }
      }
    })
  }
}

# 3. ArgoCD repository credentials (so ArgoCD can access your private Git repo)
resource "kubernetes_secret" "argocd_repo_secret" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = "repo-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url      = var.gitops_repo_url
    username = var.github_username
    password = var.github_pat
  }
  type = "Opaque"
}

# --- ArgoCD Application (the only manifest we apply) ---

resource "kubectl_manifest" "gitops_app" {
  depends_on = [
    helm_release.argocd,
    kubernetes_secret.argocd_repo_secret,
    kubernetes_secret.cloudflare_tunnel_token,
    kubernetes_secret.ghcr_credentials
  ]
  yaml_body = file("${path.module}/../../gitops/app.yaml")
}