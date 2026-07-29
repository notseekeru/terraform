provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.kube/config")
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config")
}

provider "kubectl" {
  config_path       = pathexpand("~/.kube/config")
  load_config_file  = true
}
