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
        # No security_context override: postgres:16-alpine defaults to uid 999.
        # Explicit fs_group/run_as_user caused chmod denial on local-path PV mounts.
        container {
          name              = "postgres"
          image             = "postgres:18-alpine"
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
          # PG18+ image stores data under /var/lib/postgresql/<major>/docker and
          # refuses a flat mount at /var/lib/postgresql/data (docker-library/postgres#1259).
          # Mount the volume at the parent so the entrypoint can initdb into its
          # versioned subdir (pg_upgrade-compatible layout).
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql"
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

# The same pull secret in each app namespace: `imagePullSecrets` are NAMESPACE-LOCAL, so a workload
# in `maxterview` cannot see the copy in `default` — without this every pod (and the PreSync migrate
# Job, which then aborts the whole sync) sits in ImagePullBackOff. Deliberately a separate resource
# from the one above so the existing `default` secret is never recreated; extend the list as
# namespaces appear (staging).
resource "kubernetes_secret" "ghcr_credentials_app_ns" {
  for_each = toset([kubernetes_namespace.maxterview.metadata[0].name])

  metadata {
    name      = "ghcr-login"
    namespace = each.value
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

# maxterview lives in its own namespace (NOT `default`, unlike diagram/portfolio): the env
# dimension belongs in the namespace, so a staging namespace can be added later without the
# `maxterview-secrets`/Deployment/Service name collisions `default` would cause.
resource "kubernetes_namespace" "maxterview" {
  metadata {
    name = "maxterview"
  }
}

resource "kubernetes_secret" "maxterview_secrets" {
  metadata {
    name      = "maxterview-secrets"
    namespace = kubernetes_namespace.maxterview.metadata[0].name
  }
  # Keys are the app's env var names verbatim: the Deployment consumes this with `envFrom`.
  # UPPERCASE only — a lowercase key here would be an env var the app never reads.
  data = {
    DATABASE_URL          = var.MAXTERVIEW_DATABASE_URL
    MIGRATE_DATABASE_URL  = var.MAXTERVIEW_MIGRATE_DATABASE_URL
    CLERK_JWKS_URL        = var.MAXTERVIEW_CLERK_JWKS_URL
    CLERK_DOMAIN          = var.MAXTERVIEW_CLERK_DOMAIN
    CLERK_AUDIENCE        = var.MAXTERVIEW_CLERK_AUDIENCE
    LLM_BASE_URL          = var.MAXTERVIEW_LLM_BASE_URL
    LLM_MODEL             = var.MAXTERVIEW_LLM_MODEL
    LLM_API_KEY           = var.MAXTERVIEW_LLM_API_KEY
    STRIPE_SECRET_KEY     = var.MAXTERVIEW_STRIPE_SECRET_KEY
    STRIPE_WEBHOOK_SECRET = var.MAXTERVIEW_STRIPE_WEBHOOK_SECRET
    STRIPE_PRICE_ID       = var.MAXTERVIEW_STRIPE_PRICE_ID
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
    kubernetes_secret.maxterview_secrets,
  ]

  yaml_body = file(local.app_yaml_path)
}
