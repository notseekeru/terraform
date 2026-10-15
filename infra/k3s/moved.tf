# Delete after the v1 renames are applied to live state.
moved {
  from = kubernetes_namespace.database
  to   = kubernetes_namespace_v1.database
}

moved {
  from = kubernetes_namespace.portfolio
  to   = kubernetes_namespace_v1.portfolio
}

moved {
  from = kubernetes_namespace.diagram
  to   = kubernetes_namespace_v1.diagram
}

moved {
  from = kubernetes_namespace.maxterview
  to   = kubernetes_namespace_v1.maxterview
}

moved {
  from = kubernetes_secret.postgres_credentials
  to   = kubernetes_secret_v1.postgres_credentials
}

moved {
  from = kubernetes_secret.cloudflare_tunnel_token
  to   = kubernetes_secret_v1.cloudflare_tunnel_token
}

moved {
  from = kubernetes_secret.ghcr_credentials
  to   = kubernetes_secret_v1.ghcr_credentials
}

moved {
  from = kubernetes_secret.ghcr_credentials_app_ns
  to   = kubernetes_secret_v1.ghcr_credentials_app_ns
}

moved {
  from = kubernetes_secret.diagram_secrets
  to   = kubernetes_secret_v1.diagram_secrets
}

moved {
  from = kubernetes_secret.maxterview_secrets
  to   = kubernetes_secret_v1.maxterview_secrets
}

moved {
  from = kubernetes_secret.maxterview_logs
  to   = kubernetes_secret_v1.maxterview_logs
}

moved {
  from = kubernetes_secret.argocd_repo_secret
  to   = kubernetes_secret_v1.argocd_repo_secret
}
