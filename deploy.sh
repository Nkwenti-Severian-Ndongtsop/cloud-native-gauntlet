#!/bin/bash
set -e

# Set environment variables
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Change to the project directory
cd /vagrant

# Ensure kubectl is available
export PATH="/usr/local/bin:$PATH"

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes >/dev/null 2>&1; do
    sleep 5
done

# Create namespaces if they don't exist
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Get ArgoCD admin password
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Apply the root application
echo "Applying root application..."
kubectl apply -f argocd/apps/root-application.yaml

# Wait for applications to be ready
echo -e "\nDeployment in progress. This may take a few minutes..."
echo -e "\nYou can monitor the deployment progress in the ArgoCD UI:"
echo "- ArgoCD: http://argocd.local"
echo "  Username: admin"
echo "  Password: $ARGO_PASSWORD"

echo -e "\nOnce deployed, access the applications at:"
echo "- Keycloak: http://keycloak.local"
echo "  Admin console: http://keycloak.local/admin"
echo "  Username: admin"
echo "  Password: admin"

echo -e "\n- Gitea: http://gitea.local"
echo "  Initial setup required on first access"

echo -e "\n- Todo App: http://todo.local"

echo -e "\nTo access the applications from your host machine, ensure you have the following"
echo "entries in your /etc/hosts file (or equivalent):"
echo "192.168.56.10 keycloak.local gitea.local argocd.local todo.local"

echo -e "\nDeployment complete!"
