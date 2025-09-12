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
  for_each = toset(["keycloak", "gitea", "todo", "argocd", "drone"])
  
  metadata {
    name = each.key
  }
}

# Deploy Keycloak with CNPG PostgreSQL
resource "helm_release" "keycloak" {
  name      = "keycloak"
  chart     = "../../helm/keycloak"
  namespace = kubernetes_namespace.namespaces["keycloak"].metadata[0].name
  
  depends_on = [kubernetes_namespace.namespaces]
}

# Deploy Gitea with CNPG PostgreSQL
resource "helm_release" "gitea" {
  name      = "gitea"
  chart     = "../../helm/gitea"
  namespace = kubernetes_namespace.namespaces["gitea"].metadata[0].name
  
  depends_on = [kubernetes_namespace.namespaces]
}

# Deploy Todo App
resource "helm_release" "todo_app" {
  name       = "todo-app"
  chart      = "${path.module}/../../../helm/todo-app"
  namespace  = kubernetes_namespace.namespaces["todo"].metadata[0].name
  
  depends_on = [
    kubernetes_namespace.namespaces["todo"],
    helm_release.keycloak,
    helm_release.gitea
  ]
}

# Deploy ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  chart      = "${path.module}/../../../helm/argo-cd"
  namespace  = kubernetes_namespace.namespaces["argocd"].metadata[0].name
  
  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      server = {
        ingress = {
          enabled = true
          hosts = ["argocd.local"]
          annotations = {
            "kubernetes.io/ingress.class" = "traefik"
          }
        }
      }
    })
  ]
  
  depends_on = [kubernetes_namespace.namespaces]
}

# Wait for Keycloak pods to be ready and run setup script
resource "null_resource" "keycloak_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "⏳ Waiting for Keycloak pods to be ready..."
      
      # Wait for Keycloak pod
      timeout 300 bash -c "
        while true; do
          if vagrant ssh cloud-gauntlet -c 'kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak' | grep -q 'Running'; then
            echo '✅ Keycloak pod is running'
            break
          fi
          echo 'Waiting for Keycloak pod...'
          sleep 10
        done
      "
      
      echo "🚀 Running Keycloak setup script..."
      cd ${path.module}/../../../scripts && ./setup-keycloak.sh
    EOT
    
    working_dir = path.module
  }
  
  depends_on = [
    helm_release.keycloak,
    helm_release.todo_app
  ]
}

# Deploy Drone Server
resource "helm_release" "drone" {
  name       = "drone"
  chart      = "${path.module}/../../../helm/drone"
  namespace  = kubernetes_namespace.namespaces["drone"].metadata[0].name
  
  values = [
    yamlencode({
      ingress = {
        enabled = true
        hosts = [
          {
            host = "drone.local"
            paths = ["/"]
          }
        ]
        annotations = {
          "kubernetes.io/ingress.class" = "traefik"
        }
      }
      env = {
        DRONE_GITEA_SERVER = "http://gitea.local"
        DRONE_GITEA_CLIENT_ID = "drone"
        DRONE_GITEA_CLIENT_SECRET = "drone-secret"
        DRONE_RPC_SECRET = "super-secret-rpc-key"
        DRONE_SERVER_HOST = "drone.local"
        DRONE_SERVER_PROTO = "http"
      }
    })
  ]
  
  depends_on = [
    kubernetes_namespace.namespaces,
    helm_release.gitea
  ]
}

# Deploy Drone Runner
resource "helm_release" "drone_runner" {
  name       = "drone-runner-kube"
  chart      = "${path.module}/../../../helm/drone-runner-kube"
  namespace  = kubernetes_namespace.namespaces["drone"].metadata[0].name
  
  values = [
    yamlencode({
      env = {
        DRONE_RPC_HOST = "drone.drone.svc.cluster.local"
        DRONE_RPC_PROTO = "http"
        DRONE_RPC_SECRET = "super-secret-rpc-key"
        DRONE_NAMESPACE_DEFAULT = "drone"
      }
    })
  ]
  
  depends_on = [
    kubernetes_namespace.namespaces,
    helm_release.drone
  ]
}

# Wait for Drone pods to be ready and run setup script
resource "null_resource" "drone_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "⏳ Waiting for Drone pods to be ready..."
      
      # Wait for Drone server pod
      timeout 300 bash -c "
        while true; do
          if vagrant ssh cloud-gauntlet -c 'kubectl get pods -n drone -l app.kubernetes.io/name=drone' | grep -q 'Running'; then
            echo '✅ Drone server pod is running'
            break
          fi
          echo 'Waiting for Drone server pod...'
          sleep 10
        done
      "
      
      # Wait for Drone runner pod
      timeout 300 bash -c "
        while true; do
          if vagrant ssh cloud-gauntlet -c 'kubectl get pods -n drone -l app.kubernetes.io/name=drone-runner-kube' | grep -q 'Running'; then
            echo '✅ Drone runner pod is running'
            break
          fi
          echo 'Waiting for Drone runner pod...'
          sleep 10
        done
      "
      
      echo "🚀 Running Drone setup script..."
      cd ${path.module}/../../../scripts && ./setup-drone.sh
    EOT
    
    working_dir = path.module
  }
  
  depends_on = [
    helm_release.drone,
    helm_release.drone_runner
  ]
}

# Setup GitOps repositories and complete automation
resource "null_resource" "gitops_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "⏳ Waiting for all services to be ready..."
      
      # Wait for ArgoCD server pod
      timeout 300 bash -c "
        while true; do
          if vagrant ssh cloud-gauntlet -c 'kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server' | grep -q 'Running'; then
            echo '✅ ArgoCD server pod is running'
            break
          fi
          echo 'Waiting for ArgoCD server pod...'
          sleep 10
        done
      "
      
      echo "🚀 Running GitOps repository setup..."
      cd ${path.module}/../../../scripts && ./setup-gitops-repos.sh
    EOT
    
    working_dir = path.module
  }
  
  depends_on = [
    null_resource.keycloak_setup,
    null_resource.drone_setup,
    helm_release.argocd
  ]
}
