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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

# Configure the kubectl provider
provider "kubectl" {
  config_path      = "${path.module}/../.kube/config"
  config_context   = "default"
  apply_retry_count = 5
}

provider "kubernetes" {
  config_path    = "${path.module}/../.kube/config"
  config_context = "default"
}

provider "helm" {
  kubernetes = {
    config_path    = "${path.module}/../.kube/config"
    config_context = "default"
  }
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

# Add CloudNativePG Helm repository
resource "helm_release" "cnpg_operator" {
  name       = "cnpg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  namespace  = kubernetes_namespace_v1.cnpg_namespace.metadata[0].name
  version    = "0.19.1"  # Use the latest stable version
  wait       = true
  timeout    = 1800
  force_update = true
  create_namespace = true

  values = [
    <<-EOT
    image:
      registry: localhost:5000
      repository: cloudnative-pg/cloudnative-pg
      tag: "1.20.0"
      pullPolicy: IfNotPresent
    EOT
  ]

  depends_on = [kubernetes_namespace_v1.cnpg_namespace]
}

# Deploy Keycloak using local Helm chart with CNPG configuration
resource "helm_release" "keycloak" {
  name       = "keycloak"
  chart      = "${path.module}/../../charts/keycloak"
  namespace  = kubernetes_namespace_v1.keycloak_namespace.metadata[0].name
  wait       = true
  timeout    = 1800
  force_update = true
  recreate_pods = true
  
  # Use values from the Helm chart
  values = [
    <<-EOT
    keycloak:
      image:
        repository: "localhost:5000/keycloak/keycloak"
        tag: "26.3.3"
        pullPolicy: "IfNotPresent"
      
      # Database configuration
      db:
        vendor: postgres
        host: "keycloak-db-rw.keycloak.svc.cluster.local"
        port: 5432
        name: keycloak
        username: postgres
        existingSecret: keycloak-db-credentials
      
      # Admin user configuration
      auth:
        adminUser: admin
        adminPassword: admin
        managementUser: manager
        managementPassword: manager
      
      # Resource configuration
      resources:
        requests:
          cpu: "500m"
          memory: "512Mi"
        limits:
          cpu: "1000m"
          memory: "1Gi"
      
      # Enable CNPG integration
      cnpg:
        enabled: true
        cluster:
          name: keycloak-db
          namespace: keycloak
          instances: 1
          imageName: "localhost:5000/cloudnative-pg/postgresql:14"
          storage:
            size: "512Mi"
            storageClass: ""
          walStorage:
            size: "512Mi"
            storageClass: ""
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
    EOT
  ]

  # Add a delay to ensure the CNPG operator is fully ready
  provisioner "local-exec" {
    command = "sleep 30"
  }

  depends_on = [
    kubernetes_namespace_v1.keycloak_namespace,
    helm_release.cnpg_operator
  ]
}

# Deploy Gitea using local Helm chart
resource "helm_release" "gitea" {
  name       = "gitea"
  chart      = "${path.module}/../../charts/gitea"
  namespace  = kubernetes_namespace_v1.gitea_namespace.metadata[0].name
  wait       = true
  timeout    = 900
  force_update = true
  recreate_pods = true

  depends_on = [
    kubernetes_namespace_v1.gitea_namespace,
    helm_release.cnpg_operator
  ]
}

# Deploy ArgoCD using kubectl apply (since it's not a Helm chart)

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
