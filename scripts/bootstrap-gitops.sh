#!/bin/bash

# Complete GitOps Bootstrap Automation
# This script creates the full CI/CD pipeline without any UI interaction

set -e

echo "🚀 Bootstrapping Complete GitOps Pipeline..."

# Configuration
GITEA_URL="http://gitea.local"
DRONE_URL="http://drone.local"
ARGOCD_URL="http://argocd.local"
VM_NAME="cloud-gauntlet"
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD="r8sA8CPHD9!bt6d"
DRONE_ADMIN_USER="nkwenti"

# Repository names
APP_REPO="todo-app-source"
INFRA_REPO="todo-app-infra"

# Function to run kubectl commands inside the VM
run_kubectl() {
    vagrant ssh $VM_NAME -c "kubectl $*"
}

# Function to make API calls to Gitea
gitea_api() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -n "$data" ]; then
        curl -s -X $method \
            -H "Content-Type: application/json" \
            -u "$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD" \
            -d "$data" \
            "$GITEA_URL/api/v1$endpoint"
    else
        curl -s -X $method \
            -H "Content-Type: application/json" \
            -u "$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD" \
            "$GITEA_URL/api/v1$endpoint"
    fi
}

# Function to make API calls to Drone
drone_api() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    # Get Drone token first
    local drone_token=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$DRONE_ADMIN_USER\",\"password\":\"password\"}" \
        "$DRONE_URL/api/user/token" | jq -r '.access_token')
    
    if [ -n "$data" ]; then
        curl -s -X $method \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $drone_token" \
            -d "$data" \
            "$DRONE_URL/api$endpoint"
    else
        curl -s -X $method \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $drone_token" \
            "$DRONE_URL/api$endpoint"
    fi
}

echo "📋 Step 1: Waiting for all services to be ready..."

# Wait for Gitea
timeout 300 bash -c "
    while ! curl -s $GITEA_URL/api/v1/version >/dev/null 2>&1; do
        echo 'Waiting for Gitea API...'
        sleep 10
    done
"

# Wait for Drone
timeout 300 bash -c "
    while ! curl -s $DRONE_URL/api/user >/dev/null 2>&1; do
        echo 'Waiting for Drone API...'
        sleep 10
    done
"

echo "📋 Step 2: Creating Gitea repositories..."

# Create application source repository
echo "Creating $APP_REPO repository..."
gitea_api POST "/user/repos" '{
    "name": "'$APP_REPO'",
    "description": "Todo App Source Code with CI/CD Pipeline",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
}'

# Create infrastructure repository  
echo "Creating $INFRA_REPO repository..."
gitea_api POST "/user/repos" '{
    "name": "'$INFRA_REPO'",
    "description": "Todo App Infrastructure and Helm Charts for GitOps",
    "private": false,
    "auto_init": true,
    "default_branch": "main"
}'

echo "📋 Step 3: Setting up local git repositories..."

# Create local directories
mkdir -p /tmp/gitops-bootstrap
cd /tmp/gitops-bootstrap

# Clone repositories
git clone $GITEA_URL/$GITEA_ADMIN_USER/$APP_REPO.git
git clone $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO.git

echo "📋 Step 4: Setting up application source repository..."

cd $APP_REPO

# Copy Todo app source code
cp -r /home/nkwentiseverian/projects/cloud-Native-guantlet/todo_app/* .

# Create Drone CI pipeline
cat > .drone.yml << 'EOF'
---
kind: pipeline
type: kubernetes
name: todo-app-ci-cd

metadata:
  namespace: drone-builds

steps:
  # Build Rust application
  - name: build-rust-app
    image: 192.168.56.10:5000/rust:1.70
    commands:
      - echo "🔨 Building Rust Todo application..."
      - cargo build --release
      - echo "✅ Build completed"
    volumes:
      - name: cargo-cache
        path: /usr/local/cargo/registry

  # Run tests
  - name: test-rust-app
    image: 192.168.56.10:5000/rust:1.70
    commands:
      - echo "🧪 Running tests..."
      - cargo test
      - echo "✅ Tests passed"
    volumes:
      - name: cargo-cache
        path: /usr/local/cargo/registry
    depends_on:
      - build-rust-app

  # Build Docker image
  - name: build-docker-image
    image: 192.168.56.10:5000/docker:dind
    privileged: true
    commands:
      - echo "📦 Building Docker image..."
      - docker build -t 192.168.56.10:5000/nkwenti-severian-ndongtsop/todo-api:${DRONE_COMMIT_SHA:0:8} .
      - docker build -t 192.168.56.10:5000/nkwenti-severian-ndongtsop/todo-api:latest .
      - echo "✅ Docker image built"
    volumes:
      - name: docker-sock
        path: /var/run/docker.sock
    depends_on:
      - test-rust-app

  # Push to registry
  - name: push-docker-image
    image: 192.168.56.10:5000/docker:dind
    commands:
      - echo "🚀 Pushing to local registry..."
      - docker push 192.168.56.10:5000/nkwenti-severian-ndongtsop/todo-api:${DRONE_COMMIT_SHA:0:8}
      - docker push 192.168.56.10:5000/nkwenti-severian-ndongtsop/todo-api:latest
      - echo "✅ Image pushed successfully"
    volumes:
      - name: docker-sock
        path: /var/run/docker.sock
    depends_on:
      - build-docker-image

  # Update GitOps repository
  - name: update-gitops-repo
    image: 192.168.56.10:5000/alpine/git:latest
    environment:
      GITEA_TOKEN:
        from_secret: gitea_token
    commands:
      - echo "🔄 Updating GitOps repository..."
      - apk add --no-cache yq curl
      - git config --global user.email "drone@drone.local"
      - git config --global user.name "Drone CI"
      
      # Clone infra repo
      - git clone http://gitea_admin:$GITEA_TOKEN@gitea.local/gitea_admin/todo-app-infra.git /tmp/infra
      - cd /tmp/infra
      
      # Update image tag in Helm values
      - yq eval '.todoApp.image.tag = "${DRONE_COMMIT_SHA:0:8}"' -i helm/todo-app/values.yaml
      
      # Commit and push changes
      - git add .
      - git commit -m "🚀 Update Todo app image to ${DRONE_COMMIT_SHA:0:8}" || echo "No changes to commit"
      - git push origin main
      
      - echo "✅ GitOps repository updated"
    depends_on:
      - push-docker-image
    when:
      branch:
        - main

volumes:
  - name: cargo-cache
    temp: {}
  - name: docker-sock
    host:
      path: /var/run/docker.sock

trigger:
  branch:
    - main
  event:
    - push
EOF

# Commit and push
git add .
git commit -m "🚀 Initial Todo app source with CI/CD pipeline"
git push origin main

echo "📋 Step 5: Setting up infrastructure repository..."

cd ../$INFRA_REPO

# Copy Helm charts
mkdir -p helm
cp -r /home/nkwentiseverian/projects/cloud-Native-guantlet/helm/todo-app helm/

# Create ArgoCD Application manifest
mkdir -p argocd
cat > argocd/todo-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: todo-app-gitops
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "30"
spec:
  project: default
  source:
    repoURL: $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO.git
    targetRevision: HEAD
    path: helm/todo-app
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

# Create README
cat > README.md << EOF
# Todo App Infrastructure

This repository contains the Helm charts and ArgoCD configuration for the Todo application.

## GitOps Workflow

1. **Source Code**: Push to [$APP_REPO]($GITEA_URL/$GITEA_ADMIN_USER/$APP_REPO)
2. **CI/CD**: Drone builds and pushes new image
3. **GitOps**: Drone updates this repo with new image tag
4. **Deployment**: ArgoCD syncs changes to Kubernetes cluster

## Structure

- \`helm/todo-app/\` - Helm chart for Todo application
- \`argocd/\` - ArgoCD Application manifests

## Monitoring

- **ArgoCD**: $ARGOCD_URL
- **Drone CI**: $DRONE_URL
- **Gitea**: $GITEA_URL
EOF

# Commit and push
git add .
git commit -m "🚀 Initial infrastructure setup for GitOps"
git push origin main

echo "📋 Step 6: Configuring Drone CI/CD..."

# Activate repositories in Drone
echo "Activating $APP_REPO in Drone..."
drone_api POST "/repos/$GITEA_ADMIN_USER/$APP_REPO" '{
    "active": true,
    "protected": false,
    "trusted": true
}'

# Add Gitea token secret to Drone
echo "Adding Gitea token secret to Drone..."
drone_api POST "/repos/$GITEA_ADMIN_USER/$APP_REPO/secrets" '{
    "name": "gitea_token",
    "data": "'$GITEA_ADMIN_PASSWORD'",
    "pull_request": false
}'

echo "📋 Step 7: Setting up ArgoCD Application..."

# Apply ArgoCD Application
run_kubectl apply -f /tmp/gitops-bootstrap/$INFRA_REPO/argocd/todo-app.yaml

echo "✅ GitOps Bootstrap Complete!"
echo ""
echo "🎉 Complete CI/CD Pipeline Ready!"
echo ""
echo "📋 GitOps Workflow:"
echo "  1. Push code to: $GITEA_URL/$GITEA_ADMIN_USER/$APP_REPO"
echo "  2. Drone builds: $DRONE_URL"
echo "  3. Updates infra: $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO"
echo "  4. ArgoCD syncs: $ARGOCD_URL"
echo ""
echo "🔧 Test the Pipeline:"
echo "  cd /tmp/gitops-bootstrap/$APP_REPO"
echo "  echo '// Test change' >> src/main.rs"
echo "  git add . && git commit -m 'Test pipeline' && git push"
echo ""
echo "🚀 Your complete GitOps pipeline is now automated!"

# Cleanup
cd /home/nkwentiseverian/projects/cloud-Native-guantlet
rm -rf /tmp/gitops-bootstrap
