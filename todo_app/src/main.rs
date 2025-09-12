mod db;
mod handlers;
mod models;

use axum::{
    http::HeaderValue,
    routing::{get, post},
    Router,
};
use dotenvy::dotenv;
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::{env, net::SocketAddr};
use tower::ServiceBuilder;
use tower_http::cors::{Any, CorsLayer};

#[derive(Clone)]
pub struct AppState {
    pub db_pool: PgPool,
    pub keycloak_url: String,
    pub keycloak_realm: String,
    pub jwks_url: String,
}

#[tokio::main]
async fn main() {
    // Load environment variables from .env file for local development
    dotenv().ok();

    // Get configuration from environment variables
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let keycloak_url = env::var("KEYCLOAK_URL").expect("KEYCLOAK_URL must be set");
    let keycloak_realm = env::var("KEYCLOAK_REALM").expect("KEYCLOAK_REALM must be set");

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

    // Get JWKS URL from Keycloak using standard OIDC discovery
    let oidc_config_url = format!(
        "{}/realms/{}/.well-known/openid-configuration",
        keycloak_url, keycloak_realm
    );

    println!("Fetching OIDC configuration to get JWKS URL");
    let oidc_config: serde_json::Value = reqwest::get(&oidc_config_url)
        .await
        .expect("Failed to fetch OIDC configuration")
        .json()
        .await
        .expect("Failed to parse OIDC configuration JSON");

    let jwks_url = oidc_config["jwks_uri"]
        .as_str()
        .expect("jwks_uri not found in OIDC configuration")
        .to_string();

    // Configure CORS to allow requests from Keycloak and local development
    let cors = CorsLayer::new()
        .allow_origin(keycloak_url.clone().parse::<HeaderValue>().unwrap())
        .allow_methods(Any)
        .allow_headers(Any);

    // Create the application state
    let app_state = AppState {
        db_pool: pool.clone(),
        keycloak_url: keycloak_url.clone(),
        keycloak_realm: keycloak_realm.clone(),
        jwks_url,
    };

    // Build our application router with CORS and state
    let app = Router::new()
        // Authentication routes (no auth required)
        .route("/auth/register", post(handlers::register_handler))
        .route("/auth/login", post(handlers::login_handler))
        // Task routes (auth required)
        .route("/tasks", post(handlers::create_task_handler))
        .route("/tasks", get(handlers::get_tasks_handler))
        // Health check (configurable path)
        .route("/health", get(|| async { "Todo api is up and running" }))
        .with_state(app_state)
        .layer(ServiceBuilder::new().layer(cors));

    // Hardcoded server configuration
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080)); // Use port 8080 as standard
    println!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
