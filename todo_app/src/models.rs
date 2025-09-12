use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use time::OffsetDateTime;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Task {
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    pub user_id: String, // Keycloak user ID (string)
    pub title: String,
    pub is_completed: bool,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

// This struct will be used for creating new tasks from a POST request.
#[derive(Debug, Deserialize)]
pub struct CreateTask {
    pub title: String,
}

// Models for authentication with Keycloak
#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub email: String,
    pub password: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: i64,
    pub refresh_token: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
}

// Keycloak user creation payload
#[derive(Debug, Serialize)]
pub struct KeycloakUser {
    pub username: String,
    pub email: String,
    pub enabled: bool,
    pub credentials: Vec<KeycloakCredential>,
    #[serde(rename = "firstName")]
    pub first_name: Option<String>,
    #[serde(rename = "lastName")]
    pub last_name: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct KeycloakCredential {
    #[serde(rename = "type")]
    pub credential_type: String,
    pub value: String,
    pub temporary: bool,
}
