output "keycloak_url" {
  description = "The URL for the Keycloak admin console"
  value       = "http://keycloak.local"
}

output "keycloak_admin_username" {
  description = "The admin username for Keycloak"
  value       = "admin"
}

output "keycloak_admin_password" {
  description = "The admin password for Keycloak"
  value       = "admin"
  sensitive   = true
}

output "gitea_url" {
  description = "The URL for Gitea"
  value       = "http://gitea.local"
}

output "gitea_admin_username" {
  description = "The admin username for Gitea"
  value       = "gitea_admin"
}

output "gitea_admin_password" {
  description = "The admin password for Gitea"
  value       = "gitea_password"
  sensitive   = true
}

output "todo_app_url" {
  description = "The URL for the Todo application"
  value       = "http://todo.local"
}

output "argocd_url" {
  description = "The URL for ArgoCD"
  value       = "http://argocd.local"
}

output "argocd_admin_username" {
  description = "The admin username for ArgoCD"
  value       = "admin"
}

output "argocd_admin_password" {
  description = "The admin password for ArgoCD (check secret in argocd namespace)"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}

output "drone_url" {
  description = "The URL for Drone CI/CD"
  value       = "http://drone.local"
}

output "drone_rpc_secret" {
  description = "The RPC secret for Drone runner communication"
  value       = "super-secret-rpc-key"
  sensitive   = true
}
