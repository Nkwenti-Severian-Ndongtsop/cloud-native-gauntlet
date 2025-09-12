terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
  }
}

# Create namespaces
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(["keycloak", "gitea", "todo"])
  
  metadata {
    name = each.key
  }
}

# Deploy Keycloak with CNPG PostgreSQL
resource "helm_release" "keycloak" {
  name      = "keycloak"
  chart     = "../../charts/keycloak"
  namespace = kubernetes_namespace.namespaces["keycloak"].metadata[0].name
  
  depends_on = [kubernetes_namespace.namespaces]
}

# Deploy Gitea with CNPG PostgreSQL
resource "helm_release" "gitea" {
  name      = "gitea"
  chart     = "../../charts/gitea"
  namespace = kubernetes_namespace.namespaces["gitea"].metadata[0].name
  
  depends_on = [kubernetes_namespace.namespaces]
}

# Deploy Todo App
resource "helm_release" "todo_app" {
  name       = "todo-app"
  chart      = "${path.module}/../../../charts/todo-app"
  namespace  = kubernetes_namespace.namespaces["todo"].metadata[0].name
  
  depends_on = [
    kubernetes_namespace.namespaces["todo"],
    helm_release.keycloak,
    helm_release.gitea
  ]
}
