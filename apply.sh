#!/bin/bash
set -e

# Ensure we're in the project root
cd "$(dirname "$0")"

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Initialize Terraform
echo "Initializing Terraform..."
cd terraform
terraform init

# Apply Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve

# Copy kubeconfig to standard location
cp .kube/config ~/.kube/config
chmod 600 ~/.kube/config

# Get the hosts file content and display it
echo -e "\nDeployment complete!\n"
echo "Add the following line to your /etc/hosts file:"
cat hosts

echo -e "\nAccess the applications at:"
echo "- Keycloak: http://keycloak.local"
echo "  Username: admin"
echo "  Password: admin"

echo -e "\n- Gitea: http://gitea.local"
echo "  Username: gitea_admin"
echo "  Password: gitea_password"

echo -e "\n- Todo App: http://todo.local"

echo -e "\nYou can now use kubectl and helm commands directly from your host machine."
echo "Example:"
echo "  kubectl get pods -A"
echo "  helm list -A"
