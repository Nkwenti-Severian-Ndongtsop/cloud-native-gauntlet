terraform {
  required_version = ">= 1.4.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
  }
}

# Use explicit kubeconfig path passed from root
variable "kubeconfig_path" {
  description = "Path to kubeconfig file on host"
  type        = string
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  # This section configures the Helm provider to use the Kubernetes provider's context
  # It automatically inherits configuration from the kubernetes provider
}

variable "helm_charts_root_rel" {
  description = "Relative path (from repository root) to directory with Helm chart folders."
  type        = string
  default     = "helm"
}

locals {
  repo_root         = abspath("${path.module}/..")
  helm_charts_root  = abspath("${local.repo_root}/../${var.helm_charts_root_rel}")
  helm_chart_files  = fileset(local.helm_charts_root, "**/Chart.yaml")
  helm_chart_dirs   = [for f in local.helm_chart_files : dirname("${local.helm_charts_root}/${f}")]
  helm_releases     = { for d in local.helm_chart_dirs : basename(d) => d }
}

resource "kubernetes_namespace_v1" "helm_namespaces" {
  for_each = local.helm_releases

  metadata { name = each.key }
}

resource "helm_release" "local_charts" {
  for_each = local.helm_releases

  depends_on = [kubernetes_namespace_v1.helm_namespaces]

  name              = each.key
  chart             = each.value
  namespace         = each.key
  create_namespace  = false
  dependency_update = true
  timeout           = 600
  wait              = true
}


