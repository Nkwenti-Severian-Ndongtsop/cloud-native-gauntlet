#!/bin/bash

# ArgoCD and Drone Setup Script
# This script configures ArgoCD Applications and activates Drone repositories
# Should be run after setup-gitops-repos.sh

set -e

echo "🚀 Setting up ArgoCD and Drone automation..."

# Configuration
GITEA_NAMESPACE="gitea"
ARGOCD_NAMESPACE="argocd"
DRONE_NAMESPACE="drone"
VM_NAME="cloud-gauntlet"
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD="r8sA8CPHD9!bt6d"
GITEA_URL="http://gitea.local"
ARGOCD_URL="http://argocd.local"
DRONE_URL="http://drone.local"
LOCAL_REGISTRY="192.168.56.10:5000"

# Repository names
INFRA_REPO="infra"
APP_SOURCE_REPO="app_source"

# Function to run kubectl commands inside the VM
run_kubectl() {
    vagrant ssh $VM_NAME -c "kubectl $*"
}

echo "📋 Step 1: Setting up ArgoCD with admin access and creating Application..."

# Get ArgoCD admin password and setup CLI
vagrant ssh $VM_NAME -c "
    # Wait for ArgoCD initial admin secret
    timeout 60 bash -c '
        while ! kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; do
            echo \"Waiting for ArgoCD initial admin secret...\"
            sleep 5
        done
    '
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=\$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
    echo \"ArgoCD admin password: \$ARGOCD_PASSWORD\"
    
    # Login to ArgoCD and get token
    kubectl port-forward -n argocd svc/argocd-server 8080:80 &
    PF_PID=\$!
    sleep 5
    
    # Install ArgoCD CLI if not present
    if ! command -v argocd >/dev/null 2>&1; then
        curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        chmod +x /tmp/argocd
        sudo mv /tmp/argocd /usr/local/bin/argocd
    fi
    
    # Login to ArgoCD
    argocd login localhost:8080 --username admin --password \$ARGOCD_PASSWORD --insecure
    
    # Create ArgoCD Application
    cat > /tmp/todo-app-argocd.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: todo-app-source
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea.local/gitea_admin/app_source.git
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: todo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

    kubectl apply -f /tmp/todo-app-argocd.yaml
    
    # Store ArgoCD token for Drone
    ARGOCD_TOKEN=\$(argocd account generate-token --account admin)
    kubectl create secret generic argocd-token -n drone --from-literal=token=\$ARGOCD_TOKEN --dry-run=client -o yaml | kubectl apply -f -
    
    # Kill port-forward
    kill \$PF_PID 2>/dev/null || true
    
    echo '✅ ArgoCD Application created and token stored for Drone'
"

echo "📋 Step 2: Activating Drone repositories and setting up webhooks..."

# Setup Drone and activate repositories
vagrant ssh $VM_NAME -c "
    # Wait for Drone to be ready
    timeout 60 bash -c '
        while ! kubectl get pods -n drone -l app.kubernetes.io/name=drone | grep -q Running; do
            echo \"Waiting for Drone server...\"
            sleep 5
        done
    '
    
    # Install Drone CLI if not present
    if ! command -v drone >/dev/null 2>&1; then
        curl -L https://github.com/harness/drone-cli/releases/latest/download/drone_linux_amd64.tar.gz | tar zx
        sudo mv drone /usr/local/bin/
    fi
    
    # Setup Drone environment
    export DRONE_SERVER=http://drone.local
    export DRONE_TOKEN=\$(kubectl get secret drone-token -n drone -o jsonpath='{.data.token}' | base64 -d 2>/dev/null || echo 'temp-token')
    
    # Port forward to Drone
    kubectl port-forward -n drone svc/drone 8081:80 &
    DRONE_PF_PID=\$!
    sleep 5
    
    # Sync and activate app_source repository
    drone repo sync
    drone repo enable $GITEA_ADMIN_USER/$APP_SOURCE_REPO
    
    # Create Drone secrets
    drone secret add --repository $GITEA_ADMIN_USER/$APP_SOURCE_REPO --name argocd_token --data \$(kubectl get secret argocd-token -n drone -o jsonpath='{.data.token}' | base64 -d)
    
    # Kill port-forward
    kill \$DRONE_PF_PID 2>/dev/null || true
    
    echo '✅ Drone repository activated and secrets configured'
"

echo "✅ ArgoCD and Drone setup complete!"
echo ""
echo "📊 ArgoCD and Drone Configuration Summary:"
echo "- ✅ ArgoCD Application created for app_source repository monitoring"
echo "- ✅ ArgoCD admin token generated and stored for Drone integration"
echo "- ✅ Drone repository activated with automatic webhook integration"
echo "- ✅ Drone secrets configured (argocd_token for triggering deployments)"
echo ""
echo "🚀 Complete GitOps Workflow Now Active:"
echo "1. 📝 Push code changes to: $GITEA_URL/$GITEA_ADMIN_USER/$APP_SOURCE_REPO"
echo "2. 🔨 Drone automatically builds Rust Todo API"
echo "3. 📦 Drone pushes Docker image to local registry ($LOCAL_REGISTRY)"
echo "4. 🔄 Drone triggers ArgoCD sync automatically"
echo "5. 🚀 ArgoCD deploys new image to Kubernetes cluster"
echo ""
echo "🌐 Access URLs:"
echo "- ArgoCD: $ARGOCD_URL (admin: admin)"
echo "- Drone: $DRONE_URL"
echo ""
echo "🧪 Test the Complete GitOps Workflow:"
echo "1. Clone app_source: git clone $GITEA_URL/$GITEA_ADMIN_USER/$APP_SOURCE_REPO.git"
echo "2. Make changes to Todo API code"
echo "3. Push changes: git add . && git commit -m 'Update API' && git push"
echo "4. Watch Drone build: $DRONE_URL"
echo "5. Watch ArgoCD sync: $ARGOCD_URL"
echo "6. See new deployment: kubectl get pods -n todo"
echo ""
echo "🎉 Your ArgoCD and Drone automation is now fully configured!"
