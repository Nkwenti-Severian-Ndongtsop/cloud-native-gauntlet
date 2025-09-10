# K3s Configuration
k3s_master_ip: "${master_ip}"
k3s_worker_ips: ${jsonencode(worker_ips)}

# Registry Configuration
registry_port: 5000
registry_host: "${master_ip}"

# DNS Configuration
dns_domain: "local"
local_domains:
  - "k3s.local"
  - "gitea.local"
  - "keycloak.local"
  - "argocd.local"
  - "todo.local"

# Application Configuration
app_name: "rust-todo-api"
app_port: 8000
app_image: "localhost:5000/ghcr.io/nkwenti-severian-ndongtsop/todo-api:latest"

# Database Configuration
db_name: "todo_app"
db_user: "todo_app_user"
db_password: "todo_app_password"

# Keycloak Configuration
keycloak_realm: "todo-app"
keycloak_client_id: "todo-app-client"
keycloak_client_secret: "todo-app-secret"
