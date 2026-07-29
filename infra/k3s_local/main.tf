# --- Locals ---

locals {
  app_yaml_path = var.app_yaml_path != null ? var.app_yaml_path : "${path.module}/../../../gitops/app.yaml"
}

# --- Nginx Ingress Controller ---

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600

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

# --- ArgoCD Installation ---

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"
  timeout          = 600
}

# --- Secrets ---

resource "kubernetes_secret" "cloudflare_tunnel_token" {
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

resource "kubernetes_secret" "diagram_secrets" {
  metadata {
    name      = "diagram-secrets"
    namespace = "default"
  }
  data = {
    api_key      = var.DIAGRAM_API_KEY
    database_url = var.DIAGRAM_DB_URL
  }
  type = "Opaque"
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

# --- ArgoCD Application ---

resource "kubectl_manifest" "gitops_app" {
  depends_on = [
    helm_release.argocd,
    helm_release.ingress_nginx,
    kubernetes_secret.argocd_repo_secret,
    kubernetes_secret.cloudflare_tunnel_token,
    kubernetes_secret.ghcr_credentials,
    kubernetes_secret.diagram_secrets,
  ]

  yaml_body = file(local.app_yaml_path)
}
