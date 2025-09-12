#!/bin/bash
set -e

# Images actually used by current manifests
IMAGES=(
  # CNPG
  "ghcr.io/cloudnative-pg/cloudnative-pg:1.20.0"
  "ghcr.io/cloudnative-pg/postgresql:14"

  # Keycloak
  "quay.io/keycloak/keycloak:26.3.3"

  # Gitea
  "gitea/gitea:1.20.5"

  # ArgoCD stack
  "quay.io/argoproj/argocd:v3.1.5"
  "ghcr.io/dexidp/dex:v2.43.0"
  "public.ecr.aws/docker/library/redis:7.2.7-alpine"
  "ghcr.io/oliver006/redis_exporter:v1.77.0"
  "quay.io/argoprojlabs/argocd-extension-installer:v0.0.8"
  "public.ecr.aws/docker/library/haproxy:2.8-alpine"
  "koalaman/shellcheck:v0.10.0"
  "busybox:1.36"

  # Drone CI/CD stack
  "drone/drone:2.24.0"
  "drone/drone-runner-kube:1.0.0-rc.3"

  # todo-api
  "ghcr.io/nkwenti-severian-ndongtsop/todo-api:latest"
)

# Pull and save images
for image in "${IMAGES[@]}"; do
  echo "Pulling $image..."
  docker pull "$image"
  
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
    elif [[ "$image" == "public.ecr.aws/"* ]]; then
      local_tag_name="${image#public.ecr.aws/}"
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
    
    # Also tag and push to VM IP for cross-node clarity
    docker tag "$image" "192.168.56.10:5000/$local_tag_name"
    docker push "192.168.56.10:5000/$local_tag_name"
  fi
done

echo "\nAll images have been saved to the registry."
