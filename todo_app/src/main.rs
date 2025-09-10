// Declare our new modules
mod db;
mod handlers;
mod models;

use axum::{
    routing::{get, post},
    Router,
};
use sqlx::postgres::{PgPoolOptions, PgPool};
use std::net::SocketAddr;
use dotenvy::dotenv;
use std::env;
use std::collections::HashMap;
use std::sync::Arc;
use jsonwebtoken::DecodingKey;

// --- THIS STRUCT IS NOW PUBLIC ---
// This allows other modules in our crate to use it.
#[derive(Clone)]
pub struct AppState {
    pub db_pool: PgPool,
    pub keycloak_url: String,
    pub keycloak_realm: String,
    pub jwks: Arc<HashMap<String, DecodingKey>>,
}
// ---------------------------------

#[tokio::main]
async fn main() {
    // Load environment variables from .env file for local development
    dotenv().ok();

    // Get database and Keycloak configuration from environment variables
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let keycloak_url = env::var("KEYCLOAK_URL").expect("KEYCLOAK_URL must be set");
    let keycloak_realm = env::var("KEYCLOAK_REALM").unwrap_or_else(|_| "todo-app".to_string());

    // Create a database connection pool
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to create database pool.");
    println!("Database pool created successfully.");

    // Run database migrations on startup
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run database migrations.");
    println!("Database migrations ran successfully.");

    // Discover OIDC configuration and fetch JWKS once at startup
    let oidc_config_url = format!(
        "{}/realms/{}/.well-known/openid-configuration",
        keycloak_url, keycloak_realm
    );
    let oidc_config: serde_json::Value = reqwest::get(&oidc_config_url)
        .await
        .expect("Failed to fetch OIDC configuration")
        .json()
        .await
        .expect("Failed to parse OIDC configuration JSON");

    // Prefer explicit KEYCLOAK_JWKS_URL if provided to avoid external hostnames in discovery
    let jwks_url = env::var("KEYCLOAK_JWKS_URL")
        .ok()
        .unwrap_or_else(|| oidc_config["jwks_uri"].as_str().expect("jwks_uri not found").to_string());

    let jwks: serde_json::Value = reqwest::get(&jwks_url)
        .await
        .expect("Failed to fetch JWKS")
        .json()
        .await
        .expect("Failed to parse JWKS JSON");

    // Build a map of kid -> DecodingKey
    let mut kid_to_key: HashMap<String, DecodingKey> = HashMap::new();
    if let Some(keys) = jwks.get("keys").and_then(|k| k.as_array()) {
        for k in keys {
            if let (Some(kid), Some(n), Some(e)) = (
                k.get("kid").and_then(|v| v.as_str()),
                k.get("n").and_then(|v| v.as_str()),
                k.get("e").and_then(|v| v.as_str()),
            ) {
                if let Ok(dec_key) = DecodingKey::from_rsa_components(n, e) {
                    kid_to_key.insert(kid.to_string(), dec_key);
                }
            }
        }
    }
    let jwks_arc = Arc::new(kid_to_key);

    // Create the application state
    let app_state = AppState {
        db_pool: pool.clone(),
        keycloak_url,
        keycloak_realm,
        jwks: jwks_arc,
    };

    // Build our application router with the new state
    let app = Router::new()
        .route("/tasks", post(handlers::create_task_handler))
        .route("/tasks", get(handlers::get_tasks_handler))
        .route("/health", get(|| async { "ok" }))
        .with_state(app_state);

    // Run our application
    let addr = SocketAddr::from(([0, 0, 0, 0], 8000));
    println!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}