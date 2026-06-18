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

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.lab_cluster.endpoint
  token                  = digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.lab_cluster.kube_config.0.cluster_ca_certificate)
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  depends_on       = [digitalocean_kubernetes_cluster.lab_cluster]
}

resource "kubernetes_manifest" "gitops_app" {
  depends_on = [helm_release.argocd]  # wait for ArgoCD to be installed

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "gitops"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/notseekeru/gitops.git"
        path           = "."
        targetRevision = "main"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "nginx_ingress" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "ingress-nginx"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL = "https://kubernetes.github.io/ingress-nginx"
        chart   = "ingress-nginx"
        targetRevision = "4.11.3"
        helm = {
          values = <<-EOT
            controller:
              service:
                type: LoadBalancer
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "ingress-nginx"
      }
      syncPolicy = {
        syncOptions = [ "CreateNamespace=true" ]
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_secret" "cloudflare_token" {
  depends_on = [digitalocean_kubernetes_cluster.lab_cluster]

  metadata {
    name      = "cloudflared-token"
    namespace = "default"
  }

  data = {
    token = var.cloudflare_tunnel_token   # you must define this variable
  }

  type = "Opaque"
}