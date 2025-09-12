#!/bin/bash

# GitOps Repository Setup Script
# Creates infra and app_source repos in Gitea, copies code, and sets up basic GitOps structure

set -e

echo "🚀 Setting up GitOps repositories..."

# Configuration
GITEA_NAMESPACE="gitea"
VM_NAME="cloud-gauntlet"
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD="r8sA8CPHD9!bt6d"
GITEA_URL="http://gitea.local"

# Repository names
INFRA_REPO="infra"
APP_SOURCE_REPO="app_source"

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
            echo '✅ Gitea pod is running'
            break
        fi
        echo 'Waiting for Gitea pod...'
        sleep 10
    done
"

echo "📋 Step 2: Getting Gitea admin token and creating repositories..."

# Get Gitea admin token
GITEA_TOKEN=$(vagrant ssh $VM_NAME -c "kubectl get secret gitea-admin-secret -n $GITEA_NAMESPACE -o jsonpath='{.data.token}' | base64 -d" 2>/dev/null || echo "")

if [ -z "$GITEA_TOKEN" ]; then
    echo "⚠️  Gitea admin token not found, creating one..."
    vagrant ssh $VM_NAME -c "
        # Create admin token via Gitea CLI
        kubectl exec -n $GITEA_NAMESPACE \$(kubectl get pods -n $GITEA_NAMESPACE -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}') -- \
        gitea admin user generate-access-token --username $GITEA_ADMIN_USER --token-name automation --scopes write:repository,write:user,write:admin > /tmp/gitea-token.txt
        
        # Store token in secret
        kubectl create secret generic gitea-admin-secret -n $GITEA_NAMESPACE --from-literal=token=\$(cat /tmp/gitea-token.txt | grep 'Access token' | awk '{print \$NF}') --dry-run=client -o yaml | kubectl apply -f -
    "
    GITEA_TOKEN=$(vagrant ssh $VM_NAME -c "kubectl get secret gitea-admin-secret -n $GITEA_NAMESPACE -o jsonpath='{.data.token}' | base64 -d")
fi

echo "✅ Gitea admin token obtained"

# Create infra repository
echo "Creating infra repository..."
vagrant ssh $VM_NAME -c "
    curl -X POST '$GITEA_URL/api/v1/user/repos' \
        -H 'Authorization: token $GITEA_TOKEN' \
        -H 'Content-Type: application/json' \
        -d '{
            \"name\": \"$INFRA_REPO\",
            \"description\": \"Infrastructure as Code repository\",
            \"private\": false,
            \"auto_init\": true
        }' || echo 'Repository may already exist'
"

# Create app_source repository
echo "Creating app_source repository..."
vagrant ssh $VM_NAME -c "
    curl -X POST '$GITEA_URL/api/v1/user/repos' \
        -H 'Authorization: token $GITEA_TOKEN' \
        -H 'Content-Type: application/json' \
        -d '{
            \"name\": \"$APP_SOURCE_REPO\",
            \"description\": \"Application source code repository\",
            \"private\": false,
            \"auto_init\": true
        }' || echo 'Repository may already exist'
"

echo "📋 Step 3: Setting up local git repositories and copying code..."

# Setup infra repository
echo "Setting up infra repository..."
vagrant ssh $VM_NAME -c "
    cd /tmp
    rm -rf $INFRA_REPO || true
    git clone $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO.git
    cd $INFRA_REPO
    
    # Copy infrastructure code
    cp -r /vagrant/helm ./
    cp -r /vagrant/terraform ./
    cp -r /vagrant/scripts ./
    cp /vagrant/Vagrantfile ./
    cp /vagrant/ansible.cfg ./
    cp -r /vagrant/group_vars ./
    cp -r /vagrant/roles ./
    cp /vagrant/playbook.yml ./
    
    # Create README for infra repo
    cat > README.md << 'EOF'
# Infrastructure Repository

This repository contains all infrastructure as code for the cloud-native application stack.

## Structure
- \`helm/\` - Helm charts for all applications
- \`terraform/\` - Terraform infrastructure code
- \`scripts/\` - Automation and setup scripts
- \`roles/\` - Ansible roles for VM provisioning

## Deployment
Run \`terraform apply\` to deploy the complete stack.
EOF

    git add .
    git config user.email 'admin@gitea.local'
    git config user.name '$GITEA_ADMIN_USER'
    git commit -m 'Initial infrastructure commit' || true
    git push origin main || git push origin master
"

# Setup app_source repository
echo "Setting up app_source repository..."
vagrant ssh $VM_NAME -c "
    cd /tmp
    rm -rf $APP_SOURCE_REPO || true
    git clone $GITEA_URL/$GITEA_ADMIN_USER/$APP_SOURCE_REPO.git
    cd $APP_SOURCE_REPO
    
    # Copy Todo app source code
    cp -r /vagrant/todo-api ./
    
    # Create Dockerfile for Todo app (if not exists)
    if [ ! -f todo-api/Dockerfile ]; then
        cat > todo-api/Dockerfile << 'EOF'
# Multi-stage build for Rust Todo API
FROM rust:1.75 as builder

WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/todo-api /app/todo-api
COPY --from=builder /app/migrations /app/migrations

EXPOSE 8080
CMD [\"./todo-api\"]
EOF
    fi
    
    # Create Drone CI pipeline
    cat > .drone.yml << 'EOF'
kind: pipeline
type: kubernetes
name: todo-api-build

steps:
- name: build-and-push
  image: plugins/docker
  settings:
    registry: 192.168.56.10:5000
    repo: 192.168.56.10:5000/nkwenti-severian-ndongtsop/todo-api
    tags:
      - latest
      - \${DRONE_COMMIT_SHA:0:8}
    dockerfile: todo-api/Dockerfile
    context: todo-api
    insecure: true
  when:
    branch: 
    - main
    - master

- name: trigger-argocd
  image: curlimages/curl
  commands:
    - |
      curl -X POST http://argocd-server.argocd.svc.cluster.local/api/v1/applications/todo-app/sync \
        -H \"Authorization: Bearer \$ARGOCD_TOKEN\" \
        -H \"Content-Type: application/json\" \
        -d '{\"revision\": \"HEAD\"}'
  environment:
    ARGOCD_TOKEN:
      from_secret: argocd_token
  when:
    branch: 
    - main
    - master

trigger:
  branch:
  - main
  - master
EOF
    
    # Create README for app_source repo
    cat > README.md << 'EOF'
# Application Source Repository

This repository contains the Todo API application source code.

## Structure
- \`todo-api/\` - Rust Todo API application
- \`.drone.yml\` - Drone CI/CD pipeline configuration

## CI/CD Pipeline
The Drone pipeline will:
1. Build the Rust application
2. Create Docker image
3. Push to local registry (192.168.56.10:5000)
4. Trigger ArgoCD sync to deploy new image

## Development
Make changes to the Todo API code and push to trigger the CI/CD pipeline.
EOF

    git add .
    git config user.email 'admin@gitea.local'
    git config user.name '$GITEA_ADMIN_USER'
    git commit -m 'Initial application source commit' || true
    git push origin main || git push origin master
"

echo "✅ GitOps repositories setup complete!"
echo ""
echo "📊 Repository Setup Summary:"
echo "- ✅ Created infra repository: $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO"
echo "- ✅ Created app_source repository: $GITEA_URL/$GITEA_ADMIN_USER/$APP_SOURCE_REPO"
echo "- ✅ Copied and pushed infrastructure code to infra repo"
echo "- ✅ Copied and pushed Todo app code to app_source repo"
echo "- ✅ Created Drone CI/CD pipeline (.drone.yml) with build → push → deploy workflow"
echo ""
echo "🌐 Repository URLs:"
echo "- Gitea: $GITEA_URL (admin: $GITEA_ADMIN_USER)"
echo "- Infra Repo: $GITEA_URL/$GITEA_ADMIN_USER/$INFRA_REPO"
echo "- App Source Repo: $GITEA_URL/$GITEA_ADMIN_USER/$APP_SOURCE_REPO"
echo ""
echo "🔧 Next Steps:"
echo "1. ArgoCD and Drone configuration will be handled by setup-argocd-drone.sh"
echo "2. This enables the complete GitOps workflow: Push → Build → Deploy"
echo ""
echo "🎉 Repository setup complete! Ready for ArgoCD and Drone configuration."
