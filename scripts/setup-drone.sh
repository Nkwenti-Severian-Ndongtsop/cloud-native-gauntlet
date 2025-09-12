#!/bin/bash

# Drone CI/CD Setup Script
# This script configures Drone CI/CD integration with Gitea

set -e

echo "🚀 Setting up Drone CI/CD integration with Gitea..."

# Configuration
GITEA_NAMESPACE="gitea"
DRONE_NAMESPACE="drone"
VM_NAME="cloud-gauntlet"
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD="r8sA8CPHD9!bt6d"

# Function to run kubectl commands inside the VM
run_kubectl() {
    vagrant ssh $VM_NAME -c "kubectl $*"
}

# Function to run commands inside Gitea pod
run_gitea_cmd() {
    local pod_name=$(run_kubectl get pods -n $GITEA_NAMESPACE -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
    vagrant ssh $VM_NAME -c "kubectl exec -n $GITEA_NAMESPACE $pod_name -- $*"
}

echo "📋 Step 1: Waiting for Gitea to be ready..."
timeout 300 bash -c "
    while true; do
        if run_kubectl get pods -n $GITEA_NAMESPACE -l app.kubernetes.io/name=gitea | grep -q 'Running'; then
            echo 'Gitea pod is running'
            break
        fi
        echo 'Waiting for Gitea pod...'
        sleep 10
    done
"

echo "📋 Step 2: Creating Drone OAuth application in Gitea..."

# Create OAuth2 application for Drone in Gitea
run_gitea_cmd gitea admin auth add-oauth \
    --name "Drone CI" \
    --provider "oauth2" \
    --key "drone-ci" \
    --secret "drone-secret-key" \
    --auto-discover-url "http://drone.local/.well-known/openid_configuration" \
    --icon-url "https://docs.drone.io/logo.svg" \
    --scopes "read:user,user:email,read:org" || echo "OAuth app may already exist"

echo "📋 Step 3: Waiting for Drone server to be ready..."
timeout 300 bash -c "
    while true; do
        if run_kubectl get pods -n $DRONE_NAMESPACE -l app.kubernetes.io/name=drone | grep -q 'Running'; then
            echo 'Drone server pod is running'
            break
        fi
        echo 'Waiting for Drone server pod...'
        sleep 10
    done
"

echo "📋 Step 4: Waiting for Drone runner to be ready..."
timeout 300 bash -c "
    while true; do
        if run_kubectl get pods -n $DRONE_NAMESPACE -l app.kubernetes.io/name=drone-runner-kube | grep -q 'Running'; then
            echo 'Drone runner pod is running'
            break
        fi
        echo 'Waiting for Drone runner pod...'
        sleep 10
    done
"

echo "📋 Step 5: Creating drone-builds namespace for CI/CD workflows..."
run_kubectl create namespace drone-builds --dry-run=client -o yaml | run_kubectl apply -f -

echo "📋 Step 6: Setting up RBAC for Drone runner in drone-builds namespace..."
cat <<EOF | run_kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: drone-builds
  name: drone-runner
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
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: drone-runner
  namespace: drone-builds
subjects:
- kind: ServiceAccount
  name: drone-runner-kube
  namespace: drone
roleRef:
  kind: Role
  name: drone-runner
  apiGroup: rbac.authorization.k8s.io
EOF

echo "✅ Drone CI/CD setup completed successfully!"
echo ""
echo "🎉 Drone CI/CD System Ready!"
echo ""
echo "📋 Access Information:"
echo "  • Drone UI: http://drone.local"
echo "  • Gitea: http://gitea.local"
echo ""
echo "🔐 Admin Credentials:"
echo "  • Drone Admin: nkwenti (auto-created)"
echo "  • Gitea Admin: $GITEA_ADMIN_USER / $GITEA_ADMIN_PASSWORD"
echo ""
echo "🚀 Next Steps:"
echo "  1. Visit http://drone.local and login with your Gitea account"
echo "  2. Activate repositories you want to build"
echo "  3. Add .drone.yml files to your repositories"
echo "  4. Push code to trigger builds!"
echo ""
echo "📖 Example .drone.yml files have been created in the examples directory"
