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
  chart      = "${path.module}/../../helm/keycloak"
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
  chart      = "${path.module}/../../helm/gitea"
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

# Deploy Drone Server using local Helm chart
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
      pullPolicy: IfNotPresent
    
    # Ingress configuration for Traefik
    ingress:
      enabled: true
      className: traefik
      annotations:
        traefik.ingress.kubernetes.io/router.entrypoints: web
      hosts:
        - host: drone.local
          paths:
            - path: /
              pathType: Prefix
      tls: []
    
    # Service configuration
    service:
      type: ClusterIP
      port: 80
      targetPort: 8080
    
    # Drone server environment variables
    env:
      # Gitea integration
      DRONE_GITEA_SERVER: "http://gitea.local"
      DRONE_GITEA_CLIENT_ID: "drone-ci"
      DRONE_GITEA_CLIENT_SECRET: "drone-secret-key"
      
      # RPC configuration
      DRONE_RPC_SECRET: "super-secret-rpc-key-for-drone"
      
      # Server configuration
      DRONE_SERVER_HOST: "drone.local"
      DRONE_SERVER_PROTO: "http"
      DRONE_SERVER_PORT: ":8080"
      
      # Database configuration (using SQLite for simplicity)
      DRONE_DATABASE_DRIVER: "sqlite3"
      DRONE_DATABASE_DATASOURCE: "/data/database.sqlite"
      
      # User and admin configuration
      DRONE_USER_CREATE: "username:nkwenti,admin:true"
      DRONE_USER_FILTER: "nkwenti"
      
      # Logs and debugging
      DRONE_LOGS_PRETTY: "true"
      DRONE_LOGS_COLOR: "true"
      DRONE_LOGS_TEXT: "true"
      
      # Registration and open registration
      DRONE_REGISTRATION_CLOSED: "false"
      
      # Repository configuration
      DRONE_REPOSITORY_FILTER: "*"
    
    # Persistent storage for Drone data
    persistentVolume:
      enabled: true
      storageClass: "local-path"
      size: 8Gi
      accessModes:
        - ReadWriteOnce
      mountPath: /data
    
    # Resource limits
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 500m
        memory: 512Mi
    
    # Security context
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.drone_namespace,
    helm_release.gitea
  ]
}

# Wait for Keycloak to be fully ready before running setup script
resource "null_resource" "wait_for_keycloak" {
  depends_on = [helm_release.keycloak]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Keycloak to be fully ready..."
      
      # Wait for Keycloak pod to be running
      timeout 300 bash -c '
        while true; do
          if vagrant ssh cloud-gauntlet -c "kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak" | grep -q "Running"; then
            echo "Keycloak pod is running"
            break
          fi
          echo "Waiting for Keycloak pod..."
          sleep 10
        done
      '
      
      # Additional wait for Keycloak to be fully initialized
      echo "Waiting additional 60 seconds for Keycloak to fully initialize..."
      sleep 60
      
      echo "Keycloak is ready for configuration"
    EOT
  }
}

# Wait for Todo app to be fully ready
resource "null_resource" "wait_for_todo_app" {
  depends_on = [helm_release.todo_app]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Todo app to be fully ready..."
      
      # Wait for Todo app pod to be running
      timeout 300 bash -c '
        while true; do
          if vagrant ssh cloud-gauntlet -c "kubectl get pods -n todo -l app.kubernetes.io/name=todo-app" | grep -q "Running"; then
            echo "Todo app pod is running"
            break
          fi
          echo "Waiting for Todo app pod..."
          sleep 10
        done
      '
      
      echo "Todo app is ready"
    EOT
  }
}

# Run Keycloak setup script after both Keycloak and Todo app are ready
resource "null_resource" "keycloak_setup" {
  depends_on = [
    null_resource.wait_for_keycloak,
    null_resource.wait_for_todo_app
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🚀 Running Keycloak setup script..."
      
      # Change to the scripts directory and run the setup script
      cd ${path.module}/../../scripts
      
      # Make sure the script is executable
      chmod +x setup-keycloak.sh
      
      # Run the Keycloak setup script
      if ./setup-keycloak.sh; then
        echo "✅ Keycloak setup completed successfully!"
      else
        echo "❌ Keycloak setup failed!"
        exit 1
      fi
    EOT
  }

  # Trigger re-run if the script changes
  triggers = {
    script_hash = filemd5("${path.module}/../../scripts/setup-keycloak.sh")
  }
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
      pullPolicy: IfNotPresent
    
    # Runner environment configuration
    env:
      # Connection to Drone server
      DRONE_RPC_HOST: "drone.drone.svc.cluster.local"
      DRONE_RPC_PROTO: "http"
      DRONE_RPC_SECRET: "super-secret-rpc-key-for-drone"
      
      # Runner configuration
      DRONE_RUNNER_CAPACITY: "2"
      DRONE_RUNNER_NAME: "drone-runner-kube"
      
      # Namespace configuration
      DRONE_NAMESPACE_DEFAULT: "drone"
      
      # Logging
      DRONE_DEBUG: "true"
      DRONE_TRACE: "true"
      
      # Resource limits for build pods
      DRONE_LIMIT_MEM: "1Gi"
      DRONE_LIMIT_CPU: "1000m"
      DRONE_REQUEST_MEM: "512Mi"
      DRONE_REQUEST_CPU: "500m"
      
      # Build timeout
      DRONE_TIMEOUT: "1h"
    
    # RBAC configuration for build namespaces
    rbac:
      buildNamespaces:
        - drone
        - drone-builds
        - default
      
      # Additional permissions for CI/CD operations
      rules:
        - apiGroups: [""]
          resources: ["pods", "pods/log", "secrets", "configmaps", "services"]
          verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
        - apiGroups: ["apps"]
          resources: ["deployments", "replicasets"]
          verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
        - apiGroups: ["batch"]
          resources: ["jobs"]
          verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
    
    # Resource limits for the runner itself
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 250m
        memory: 256Mi
    
    # Security context
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
    
    # Node selector (optional - for dedicated CI nodes)
    nodeSelector: {}
    
    # Tolerations (optional - for dedicated CI nodes)
    tolerations: []
    
    # Affinity (optional - for dedicated CI nodes)
    affinity: {}
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.drone_namespace,
    helm_release.drone
  ]
}

# Run Drone setup script after Drone server and runner are ready
resource "null_resource" "drone_setup" {
  depends_on = [
    helm_release.drone,
    helm_release.drone_runner,
    null_resource.keycloak_setup
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🚀 Running Drone CI/CD setup script..."
      
      # Change to the scripts directory and run the setup script
      cd ${path.module}/../../scripts
      
      # Make sure the script is executable
      chmod +x setup-drone.sh
      
      # Run the Drone setup script
      if ./setup-drone.sh; then
        echo "✅ Drone CI/CD setup completed successfully!"
        echo ""
        echo "🎉 Complete CI/CD Pipeline Ready!"
        echo ""
        echo "📋 CI/CD Access Information:"
        echo "  • Drone CI: http://drone.local"
        echo "  • Gitea (Git): http://gitea.local"
        echo "  • ArgoCD (GitOps): http://argocd.local"
        echo ""
        echo "🔧 Workflow Examples:"
        echo "  • Todo App Pipeline: examples/drone-workflows/.drone.yml"
        echo "  • Simple Pipeline: examples/drone-workflows/simple-pipeline.yml"
        echo ""
        echo "🚀 Your complete DevOps stack is now ready!"
      else
        echo "❌ Drone setup failed!"
        exit 1
      fi
    EOT
  }

  # Trigger re-run if the script changes
  triggers = {
    script_hash = filemd5("${path.module}/../../scripts/setup-drone.sh")
  }
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
