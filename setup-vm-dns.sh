#!/bin/bash
set -e

# Add local DNS entries to /etc/hosts
echo "Setting up local DNS entries..."
sudo bash -c 'cat >> /etc/hosts <<EOL
# Cloud Native Gauntlet Applications
127.0.0.1 keycloak.local
127.0.0.1 gitea.local
127.0.0.1 argocd.local
EOL'

echo "Local DNS entries added to /etc/hosts"
