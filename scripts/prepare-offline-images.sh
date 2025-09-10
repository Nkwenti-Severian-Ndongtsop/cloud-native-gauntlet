#!/bin/bash
set -e

# Define images to pre-pull for the 12-day cloud-native gauntlet
IMAGES=(
  # Day 1-2: Cluster Beasts - K3s and core components
  "rancher/k3s:v1.31.12-k3s1"
  "rancher/klipper-helm:v0.9.7-build20250616"
  "rancher/local-path-provisioner:v0.0.32"
  "rancher/mirrored-coredns-coredns:1.12.3"
  "rancher/mirrored-metrics-server:v0.8.0"
  "rancher/mirrored-pause:3.9"
  "registry:3.0.0"
  "debian:bookworm-slim"
  
  # Day 3-4: Application - Rust build tools
  "rust:1.87-slim"
  "alpine:3.22.1"
  
  # Day 6-7: Database & Deployment - CNPG
  "ghcr.io/cloudnative-pg/cloudnative-pg:1.20.0"
  "postgres:14-alpine"
  
  # Day 8: Keycloak
  "quay.io/keycloak/keycloak:26.3.3"
  
  # Day 9-10: GitOps - Gitea and ArgoCD
  "gitea/gitea:1.24.5"
  "argoproj/argocd:v2.6.15"
  
  # Day 11: Service Mesh - Linkerd
  "cr.l5d.io/linkerd/controller:stable-2.14.7"
)

# Create directories for offline packages
mkdir -p offline-images

# Pull and save images
for image in "${IMAGES[@]}"; do
  echo "Pulling $image..."
  docker pull "$image"
  
  # Save the image to a tar file
  filename=$(echo "$image" | sed 's/[^a-zA-Z0-9._-]/-/g').tar
  echo "Saving $image to offline-images/$filename"
  docker save -o "offline-images/$filename" "$image"
  
  # Tag and push to local registry if running
  if docker ps | grep -q registry; then
    echo "Tagging and pushing $image to local registry..."
    local_tag_name="$image"
    if [[ "$image" == "quay.io/"* ]]; then
      local_tag_name="${image#quay.io/}"
    elif [[ "$image" == "docker.io/library/"* ]]; then
      local_tag_name="${image#docker.io/library/}"
    elif [[ "$image" == "cr.l5d.io/"* ]]; then
      local_tag_name="${image#cr.l5d.io/}"
    elif [[ "$image" == "ghcr.io/"* ]]; then
      local_tag_name="${image#ghcr.io/}"
    elif [[ "$image" == "rancher/mirrored-"* ]]; then
      if [[ "$image" == "rancher/mirrored-coredns-coredns:1.12.3" ]]; then
        local_tag_name="coredns/coredns:1.12.3"
      elif [[ "$image" == "rancher/mirrored-metrics-server:v0.8.0" ]]; then
        local_tag_name="metrics-server/metrics-server:v0.8.0"
      elif [[ "$image" == "rancher/mirrored-pause:3.9" ]]; then
        local_tag_name="pause:3.9"
      else
        local_tag_name="${image#rancher/mirrored-}"
      fi
    elif [[ "$image" == "rancher/k3s:"* ]]; then
      local_tag_name="${image#rancher/}"
    elif [[ "$image" == "rancher/klipper-helm:"* ]]; then
      local_tag_name="${image#rancher/}"
    elif [[ "$image" == "rancher/local-path-provisioner:"* ]]; then
      local_tag_name="${image#rancher/}"
    else
      local_tag_name="$image"
    fi
    
    docker tag "$image" "localhost:5000/$local_tag_name"
    docker push "localhost:5000/$local_tag_name"
  fi
done

echo "\nAll images have been saved to the offline-images directory."
echo "To load these images on another machine, run:"
echo "  for img in offline-images/*.tar; do docker load -i \$img; done"
