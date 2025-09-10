#!/bin/bash
set -e

echo "🏗️  Setting up Cloud Native Gauntlet Environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Vagrant is installed
if ! command -v vagrant &> /dev/null; then
    print_error "Vagrant is not installed. Please install Vagrant first."
    exit 1
fi

# Check if VirtualBox is installed
if ! command -v VBoxManage &> /dev/null; then
    print_error "VirtualBox is not installed. Please install VirtualBox first."
    exit 1
fi

# Check if Ansible is installed
if ! command -v ansible &> /dev/null; then
    print_error "Ansible is not installed. Please install Ansible first."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

print_success "All prerequisites are installed!"

# Start VMs
print_status "Starting VMs with Vagrant..."
vagrant up

# Wait for VMs to be ready
print_status "Waiting for VMs to be ready..."
sleep 30

# Prepare offline images
print_status "Preparing offline images..."
chmod +x scripts/prepare-offline-images.sh
./scripts/prepare-offline-images.sh

# Get KUBECONFIG from master node
print_status "Setting up kubectl access..."
vagrant ssh k3s-master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Update kubeconfig with correct server IP
sed -i 's/127.0.0.1/192.168.56.10/g' kubeconfig.yaml

print_success "Environment setup completed!"

echo ""
echo "🚀 Next steps:"
echo "  1. Run: ./scripts/deploy-all.sh"
echo "  2. Access your applications at the URLs shown in the deployment output"
echo ""
echo "📝 Note: Make sure to add the following entries to your /etc/hosts file:"
echo "  192.168.56.10 k3s.local"
echo "  192.168.56.10 gitea.local"
echo "  192.168.56.10 keycloak.local"
echo "  192.168.56.10 argocd.local"
echo "  192.168.56.10 todo.local"
