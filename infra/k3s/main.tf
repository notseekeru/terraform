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

# --- PostgreSQL (StatefulSet + PVC) ---

resource "kubernetes_namespace" "database" {
  metadata {
    name = "database"
  }
}

resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "postgres-credentials"
    namespace = kubernetes_namespace.database.metadata[0].name
  }
  data = {
    password = var.POSTGRES_PASSWORD
  }
  type = "Opaque"
}

resource "kubernetes_stateful_set_v1" "postgres" {
  depends_on = [kubernetes_namespace.database]

  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.database.metadata[0].name
  }
  spec {
    service_name          = "postgres"
    replicas              = 1
    pod_management_policy = "OrderedReady"
    update_strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = {
        app = "postgres"
      }
    }
    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }
      spec {
        security_context {
          fs_group    = "999"
          run_as_user = "999"
        }
        container {
          name              = "postgres"
          image             = "postgres:16-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5432
            name           = "postgres"
          }
          env {
            name  = "POSTGRES_USER"
            value = "diagram"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "POSTGRES_DB"
            value = "diagramdb"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
            }
          }
          liveness_probe {
            tcp_socket {
              port = 5432
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "diagram", "-d", "diagramdb"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
        storage_class_name = "local-path"
      }
    }
  }
}

resource "kubernetes_service_v1" "postgres" {
  depends_on = [kubernetes_namespace.database]

  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.database.metadata[0].name
  }
  spec {
    selector = {
      app = "postgres"
    }
    port {
      port        = 5432
      target_port = 5432
    }
  }
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
  depends_on = [kubernetes_stateful_set_v1.postgres]

  metadata {
    name      = "diagram-secrets"
    namespace = "default"
  }
  data = {
    api_key      = var.DIAGRAM_API_KEY
    database_url = "postgresql://diagram:${var.POSTGRES_PASSWORD}@postgres.database.svc.cluster.local:5432/diagramdb"
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
