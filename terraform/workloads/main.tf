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

resource "kubernetes_namespace_v1" "todo_namespace" {
  metadata {
    name = "todo"
  }
}

resource "kubernetes_namespace_v1" "drone_namespace" {
  metadata {
    name = "drone"
  }
}

# Deploy CloudNativePG Operator using local official Helm chart
resource "helm_release" "cnpg_operator" {
  name      = "cnpg"
  chart     = "../../helm/cloudnative-pg"
  namespace = kubernetes_namespace_v1.cnpg_namespace.metadata[0].name
  wait      = true
  timeout   = 1800
  force_update = true
  create_namespace = false

  values = [
    <<-EOT
    image:
      repository: 192.168.56.10:5000/cloudnative-pg/cloudnative-pg
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

# Deploy Todo App using local Helm chart
resource "helm_release" "todo_app" {
  name       = "todo-app"
  chart      = "${path.module}/../../helm/todo-app"
  namespace  = kubernetes_namespace_v1.todo_namespace.metadata[0].name
  wait       = true
  timeout    = 900
  force_update = true
  recreate_pods = true

  depends_on = [
    kubernetes_namespace_v1.todo_namespace,
    helm_release.cnpg_operator
  ]
}

# Deploy ArgoCD using official Helm chart
resource "helm_release" "argocd" {
  name       = "argocd"
  chart      = "${path.module}/../../helm/argo-cd"
  namespace  = kubernetes_namespace_v1.argocd_namespace.metadata[0].name
  wait       = true
  timeout    = 900
  force_update = true
  recreate_pods = true

  values = [
    <<-EOT
    server:
      ingress:
        enabled: true
        ingressClassName: traefik
        hosts:
          - argocd.local
        paths:
          - /
        pathType: Prefix
      service:
        type: ClusterIP
    
    # Use local registry images for offline deployment
    global:
      image:
        repository: 192.168.56.10:5000/argoproj/argocd
        tag: v2.8.4
    
    controller:
      image:
        repository: 192.168.56.10:5000/argoproj/argocd
        tag: v2.8.4
    
    dex:
      image:
        repository: 192.168.56.10:5000/dexidp/dex
        tag: v2.37.0
    
    redis:
      image:
        repository: 192.168.56.10:5000/redis
        tag: 7.0.11-alpine
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.argocd_namespace
  ]
}

# Deploy Drone Server using official Helm chart
resource "helm_release" "drone" {
  name       = "drone"
  chart      = "${path.module}/../../helm/drone"
  namespace  = kubernetes_namespace_v1.drone_namespace.metadata[0].name
  wait       = true
  timeout    = 900
  force_update = true
  recreate_pods = true

  values = [
    <<-EOT
    image:
      repository: 192.168.56.10:5000/drone/drone
      tag: 2.20.0
    
    ingress:
      enabled: true
      className: traefik
      hosts:
        - host: drone.local
          paths:
            - path: /
              pathType: Prefix
    
    env:
      DRONE_GITEA_SERVER: "https://gitea.local"
      DRONE_GITEA_CLIENT_ID: "drone"
      DRONE_GITEA_CLIENT_SECRET: "drone-secret"
      DRONE_RPC_SECRET: "drone-rpc-secret"
      DRONE_SERVER_HOST: "drone.local"
      DRONE_SERVER_PROTO: "https"
    
    persistentVolume:
      enabled: true
      storageClass: "local-path"
      size: 8Gi
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.drone_namespace,
    helm_release.gitea
  ]
}

# Deploy Drone Runner using official Helm chart
resource "helm_release" "drone_runner" {
  name       = "drone-runner"
  chart      = "${path.module}/../../helm/drone-runner-kube"
  namespace  = kubernetes_namespace_v1.drone_namespace.metadata[0].name
  wait       = true
  timeout    = 900
  force_update = true
  recreate_pods = true

  values = [
    <<-EOT
    image:
      repository: 192.168.56.10:5000/drone/drone-runner-kube
      tag: 1.0.0-beta.9
    
    env:
      DRONE_RPC_HOST: "drone.drone.svc.cluster.local"
      DRONE_RPC_PROTO: "http"
      DRONE_RPC_SECRET: "drone-rpc-secret"
      DRONE_NAMESPACE_DEFAULT: "drone"
    
    rbac:
      buildNamespaces:
        - drone
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.drone_namespace,
    helm_release.drone
  ]
}

# Output useful information
output "namespaces" {
  value = [
    kubernetes_namespace_v1.cnpg_namespace.metadata[0].name,
    kubernetes_namespace_v1.keycloak_namespace.metadata[0].name,
    kubernetes_namespace_v1.gitea_namespace.metadata[0].name,
    kubernetes_namespace_v1.argocd_namespace.metadata[0].name,
    kubernetes_namespace_v1.todo_namespace.metadata[0].name,
    kubernetes_namespace_v1.drone_namespace.metadata[0].name
  ]
}

output "helm_releases" {
  value = [
    helm_release.cnpg_operator.name,
    helm_release.keycloak.name,
    helm_release.gitea.name,
    helm_release.todo_app.name,
    helm_release.argocd.name,
    helm_release.drone.name,
    helm_release.drone_runner.name
  ]
}

output "application_urls" {
  value = {
    keycloak = "https://keycloak.local"
    gitea    = "https://gitea.local"
    todo_app = "https://todo.local"
    argocd   = "https://argocd.local"
    drone    = "https://drone.local"
  }
}
