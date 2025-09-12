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
