use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use time::OffsetDateTime;

#[derive(Debug, Serialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    // Note: We will not store passwords directly in a real app,
    // but this is a placeholder until Keycloak handles it.
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Task {
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    pub user_id: Uuid,
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