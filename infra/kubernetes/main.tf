# --- Kubernetes Cluster ---

locals {
  app_yaml_path = var.app_yaml_path != null ? var.app_yaml_path : "${path.module}/../../../gitops/app.yaml"
}

resource "digitalocean_kubernetes_cluster" "lab_cluster" {
  name    = "lab-cluster"
  region  = var.default_region
  version = "1.34.8-do.2"
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

# --- Managed Database (PostgreSQL) ---

resource "digitalocean_database_cluster" "diagram_db" {
  name       = "diagram-db"
  engine     = "pg"
  version    = "16"
  size       = "db-s-1vcpu-1gb"
  region     = var.default_region
  node_count = 1

  private_network_uuid = digitalocean_kubernetes_cluster.lab_cluster.vpc_uuid
}

resource "digitalocean_database_db" "diagram_database" {
  cluster_id = digitalocean_database_cluster.diagram_db.id
  name       = "diagramdb"
}

resource "digitalocean_database_user" "diagram_user" {
  cluster_id = digitalocean_database_cluster.diagram_db.id
  name       = "diagram"
}

# --- ArgoCD Installation ---

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"
  timeout          = 600
  depends_on       = [digitalocean_kubernetes_cluster.lab_cluster]
}

# --- Nginx Ingress Controller ---

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600
  depends_on       = [digitalocean_kubernetes_cluster.lab_cluster]

  set {
    name  = "controller.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }
}

# --- Secrets ---

resource "kubernetes_secret" "cloudflare_tunnel_token" {
  depends_on = [digitalocean_kubernetes_cluster.lab_cluster]

  metadata {
    name      = "cloudflared-token"
    namespace = "default"
  }
  data = {
    token = var.CLOUDFLARE_TOKEN
  }
  type = "Opaque"
}

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
          username = var.GITHUB_USERNAME
          password = var.GITHUB_PAT
          auth     = base64encode("${var.GITHUB_USERNAME}:${var.GITHUB_PAT}")
        }
      }
    })
  }
}

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
    url      = var.GITHUB_REPO_URL
    username = var.GITHUB_USERNAME
    password = var.GITHUB_PAT
  }
  type = "Opaque"
}

resource "kubernetes_secret" "diagram_secrets" {
  depends_on = [digitalocean_kubernetes_cluster.lab_cluster]

  metadata {
    name      = "diagram-secrets"
    namespace = "default"
  }
  data = {
    api_key = var.DIAGRAM_API_KEY
    database_url = format(
      "postgresql://%s:%s@%s:25060/%s?sslmode=no-verify",
      digitalocean_database_user.diagram_user.name,
      digitalocean_database_user.diagram_user.password,
      digitalocean_database_cluster.diagram_db.private_host,
      digitalocean_database_db.diagram_database.name,
    )
  }
  type = "Opaque"
}

# --- ArgoCD Application ---

resource "kubectl_manifest" "gitops_app" {
  provider = kubectl
  depends_on = [
    digitalocean_kubernetes_cluster.lab_cluster,
    helm_release.argocd,
    helm_release.ingress_nginx,
    kubernetes_secret.argocd_repo_secret,
    kubernetes_secret.cloudflare_tunnel_token,
    kubernetes_secret.ghcr_credentials,
    kubernetes_secret.diagram_secrets
  ]
  yaml_body = file(local.app_yaml_path)
}
