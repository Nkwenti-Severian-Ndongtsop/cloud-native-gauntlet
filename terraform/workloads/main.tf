terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

# Create namespaces
resource "kubernetes_namespace_v1" "cnpg_namespace" {
  metadata {
    name = "cnpg-system"
  }
}

resource "kubernetes_namespace_v1" "keycloak_namespace" {
  metadata {
    name = "keycloak"
  }
}

resource "kubernetes_namespace_v1" "gitea_namespace" {
  metadata {
    name = "gitea"
  }
}

resource "kubernetes_namespace_v1" "argocd_namespace" {
  metadata {
    name = "argocd"
  }
}

# Deploy CNPG Operator using Helm
resource "helm_release" "cnpg_operator" {
  name       = "cnpg-operator"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.20.0"
  namespace  = kubernetes_namespace_v1.cnpg_namespace.metadata[0].name

  depends_on = [kubernetes_namespace_v1.cnpg_namespace]
}

# Deploy Keycloak using local Helm chart
resource "helm_release" "keycloak" {
  name       = "keycloak"
  chart      = "${path.module}/../../helm/keycloak"
  namespace  = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
    wait       = false
  timeout    = 900

  depends_on = [
    kubernetes_namespace_v1.keycloak_namespace,
    helm_release.cnpg_operator
  ]
}

# Deploy Gitea using local Helm chart
resource "helm_release" "gitea" {
  name       = "gitea"
  chart      = "${path.module}/../../helm/gitea"
  namespace  = kubernetes_namespace_v1.gitea_namespace.metadata[0].name
  wait       = false
  timeout    = 900

  depends_on = [
    kubernetes_namespace_v1.gitea_namespace,
    helm_release.cnpg_operator
  ]
}

# Deploy ArgoCD using kubectl apply (since it's not a Helm chart)
resource "null_resource" "argocd_install" {
  depends_on = [kubernetes_namespace_v1.argocd_namespace]

  provisioner "local-exec" {
    command = "vagrant ssh cloud-gauntlet -c 'cd /vagrant && kubectl apply -f helm/argocd/install.yaml'"
  }

  provisioner "local-exec" {
    when = destroy
    command = "vagrant ssh cloud-gauntlet -c 'cd /vagrant && kubectl delete -f helm/argocd/install.yaml --ignore-not-found=true'"
  }
}

# Deploy ArgoCD Application for infrastructure
resource "null_resource" "argocd_infra_app" {
  depends_on = [null_resource.argocd_install]

  provisioner "local-exec" {
    command = "vagrant ssh cloud-gauntlet -c 'cd /vagrant && kubectl apply -f helm/argocd/infra-app.yaml'"
  }

  provisioner "local-exec" {
    when = destroy
    command = "vagrant ssh cloud-gauntlet -c 'cd /vagrant && kubectl delete -f helm/argocd/infra-app.yaml --ignore-not-found=true'"
  }
}

# Output useful information
output "namespaces" {
  value = [
    kubernetes_namespace_v1.cnpg_namespace.metadata[0].name,
    kubernetes_namespace_v1.keycloak_namespace.metadata[0].name,
    kubernetes_namespace_v1.gitea_namespace.metadata[0].name,
    kubernetes_namespace_v1.argocd_namespace.metadata[0].name
  ]
}

output "helm_releases" {
  value = [
    helm_release.cnpg_operator.name,
    helm_release.keycloak.name,
    helm_release.gitea.name
  ]
}