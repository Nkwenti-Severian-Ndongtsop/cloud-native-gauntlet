use axum::{
    async_trait,
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    response::IntoResponse,
    Json,
};
use jsonwebtoken::{decode, decode_header, DecodingKey, Validation};
use serde::{Deserialize, Serialize};

// --- THESE `use` STATEMENTS ARE NOW CORRECTED ---
use crate::db;
use crate::models::{
    AuthResponse, CreateTask, ErrorResponse, KeycloakCredential, KeycloakUser, LoginRequest,
    RegisterRequest,
};
use crate::AppState;
use std::collections::HashMap;
// --------------------------------------------

// This struct represents the claims we expect in our JWT.
// The `sub` (subject) field is the user's ID from Keycloak.
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
}

// This struct will hold the authenticated user's ID after successful validation.
pub struct AuthenticatedUser {
    pub id: String, // User ID from JWT 'sub' claim (Keycloak user ID)
}

// JWKS are fetched and cached at startup; no structs needed here.

// This is an Axum Extractor. It runs before our handlers.
// It will check for a valid JWT and provide the user ID if successful.
// If validation fails, it automatically returns a 401 Unauthorized error.
#[async_trait]
impl FromRequestParts<AppState> for AuthenticatedUser {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // Get the Authorization header manually
        let auth_header = parts
            .headers
            .get("authorization")
            .ok_or((
                StatusCode::UNAUTHORIZED,
                "Missing Authorization header",
            ))?
            .to_str()
            .map_err(|_| (
                StatusCode::UNAUTHORIZED,
                "Invalid Authorization header format",
            ))?;

        // Extract Bearer token
        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or((
                StatusCode::UNAUTHORIZED,
                "Authorization header must start with 'Bearer '",
            ))?;

        // Find the specific key that was used to sign this token from cached JWKS.
        let header = decode_header(token)
            .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid token header"))?;
        let kid = header.kid.ok_or((
            StatusCode::BAD_REQUEST,
            "Token missing 'kid' (Key ID) in header",
        ))?;
        let decoding_key: &DecodingKey = state.jwks.get(&kid).ok_or((
            StatusCode::UNAUTHORIZED,
            "Signing key not found in JWKS cache",
        ))?;

        let mut validation = Validation::new(jsonwebtoken::Algorithm::RS256);
        validation.validate_aud = false; // For this simple case, we'll skip audience validation.

        let token_data = decode::<Claims>(token, decoding_key, &validation)
            .map_err(|_| (StatusCode::UNAUTHORIZED, "Token validation failed"))?;

        // Extract the user ID from the 'sub' claim (Keycloak user ID)
        let user_id = token_data.claims.sub;

        Ok(AuthenticatedUser { id: user_id })
    }
}

// The handlers are now much cleaner and more secure. They just take AuthenticatedUser as a parameter.
// If the token is invalid, this code will never even be reached.
pub async fn create_task_handler(
    State(state): State<AppState>,
    user: AuthenticatedUser, // The extractor provides the authenticated user's ID from JWT
    Json(new_task): Json<CreateTask>,
) -> impl IntoResponse {
    match db::create_task(&state.db_pool, user.id, new_task).await {
        Ok(task) => (StatusCode::CREATED, Json(task)).into_response(),
        Err(e) => {
            eprintln!("Failed to create task: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, "Failed to create task.").into_response()
        }
    }
}

pub async fn get_tasks_handler(
    State(state): State<AppState>,
    user: AuthenticatedUser, // Get tasks for this specific user only
) -> impl IntoResponse {
    // Get tasks for the specific user (extracted from JWT)
    match db::get_tasks_for_user(&state.db_pool, user.id).await {
        Ok(tasks) => (StatusCode::OK, Json(tasks)).into_response(),
        Err(e) => {
            eprintln!("Failed to get tasks: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, "Failed to get tasks.").into_response()
        }
    }
}

// Register a new user in Keycloak
pub async fn register_handler(
    State(state): State<AppState>,
    Json(register_req): Json<RegisterRequest>,
) -> impl IntoResponse {
    // Get Keycloak admin token
    let admin_token = match get_keycloak_admin_token(&state).await {
        Ok(token) => token,
        Err(e) => {
            eprintln!("Failed to get admin token: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "admin_token_error".to_string(),
                    message: "Failed to authenticate with Keycloak admin".to_string(),
                }),
            )
                .into_response();
        }
    };

    // Create user in Keycloak
    let keycloak_user = KeycloakUser {
        username: register_req.username.clone(),
        email: register_req.email.clone(),
        enabled: true,
        first_name: register_req.first_name.clone(),
        last_name: register_req.last_name.clone(),
        credentials: vec![KeycloakCredential {
            credential_type: "password".to_string(),
            value: register_req.password.clone(),
            temporary: false,
        }],
    };

    let client = reqwest::Client::new();
    let create_user_url = format!(
        "{}/admin/realms/{}/users",
        state.keycloak_url, state.keycloak_realm
    );

    let response = client
        .post(&create_user_url)
        .header("Authorization", format!("Bearer {}", admin_token))
        .header("Content-Type", "application/json")
        .json(&keycloak_user)
        .send()
        .await;

    match response {
        Ok(resp) => {
            if resp.status().is_success() {
                (
                    StatusCode::CREATED,
                    Json(serde_json::json!({
                        "message": "User created successfully",
                        "username": register_req.username
                    })),
                )
                    .into_response()
            } else {
                let error_text = resp.text().await.unwrap_or_default();
                eprintln!("Keycloak user creation failed: {}", error_text);
                (
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        error: "user_creation_failed".to_string(),
                        message: format!("Failed to create user: {}", error_text),
                    }),
                )
                    .into_response()
            }
        }
        Err(e) => {
            eprintln!("Failed to create user in Keycloak: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "keycloak_error".to_string(),
                    message: "Failed to communicate with Keycloak".to_string(),
                }),
            )
                .into_response()
        }
    }
}

// Login user via Keycloak and return token
pub async fn login_handler(
    State(state): State<AppState>,
    Json(login_req): Json<LoginRequest>,
) -> impl IntoResponse {
    let client = reqwest::Client::new();
    let token_url = format!(
        "{}/realms/{}/protocol/openid-connect/token",
        state.keycloak_url, state.keycloak_realm
    );

    // Get client configuration from environment
    let client_id = std::env::var("KEYCLOAK_CLIENT_ID").expect("KEYCLOAK_CLIENT_ID must be set");
    let client_secret =
        std::env::var("KEYCLOAK_CLIENT_SECRET").expect("KEYCLOAK_CLIENT_SECRET must be set");

    // Prepare form data for token request
    let mut form_data = HashMap::new();
    form_data.insert("grant_type", "password");
    form_data.insert("client_id", &client_id);
    form_data.insert("client_secret", &client_secret);
    form_data.insert("username", &login_req.username);
    form_data.insert("password", &login_req.password);

    let response = client
        .post(&token_url)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&form_data)
        .send()
        .await;

    match response {
        Ok(resp) => {
            if resp.status().is_success() {
                // Parse Keycloak token response
                match resp.json::<serde_json::Value>().await {
                    Ok(token_data) => {
                        let auth_response = AuthResponse {
                            access_token: token_data["access_token"]
                                .as_str()
                                .unwrap_or_default()
                                .to_string(),
                            token_type: token_data["token_type"]
                                .as_str()
                                .unwrap_or("Bearer")
                                .to_string(),
                            expires_in: token_data["expires_in"].as_i64().unwrap_or(300),
                            refresh_token: token_data["refresh_token"]
                                .as_str()
                                .map(|s| s.to_string()),
                        };
                        (StatusCode::OK, Json(auth_response)).into_response()
                    }
                    Err(e) => {
                        eprintln!("Failed to parse token response: {}", e);
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(ErrorResponse {
                                error: "token_parse_error".to_string(),
                                message: "Failed to parse authentication response".to_string(),
                            }),
                        )
                            .into_response()
                    }
                }
            } else {
                let error_text = resp.text().await.unwrap_or_default();
                eprintln!("Keycloak login failed: {}", error_text);
                (
                    StatusCode::UNAUTHORIZED,
                    Json(ErrorResponse {
                        error: "login_failed".to_string(),
                        message: "Invalid username or password".to_string(),
                    }),
                )
                    .into_response()
            }
        }
        Err(e) => {
            eprintln!("Failed to authenticate with Keycloak: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "keycloak_error".to_string(),
                    message: "Failed to communicate with Keycloak".to_string(),
                }),
            )
                .into_response()
        }
    }
}

// Helper function to get Keycloak admin token
async fn get_keycloak_admin_token(state: &AppState) -> Result<String, Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();
    let token_url = format!(
        "{}/realms/master/protocol/openid-connect/token",
        state.keycloak_url
    );

    // Get Keycloak admin credentials from environment variables
    let admin_username =
        std::env::var("KEYCLOAK_ADMIN_USERNAME").expect("KEYCLOAK_ADMIN_USERNAME must be set");
    let admin_password =
        std::env::var("KEYCLOAK_ADMIN_PASSWORD").expect("KEYCLOAK_ADMIN_PASSWORD must be set");

    let mut form_data = HashMap::new();
    form_data.insert("grant_type", "password");
    form_data.insert("client_id", "admin-cli");
    form_data.insert("username", &admin_username);
    form_data.insert("password", &admin_password);

    let response = client
        .post(&token_url)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&form_data)
        .send()
        .await?;

    if response.status().is_success() {
        let token_data: serde_json::Value = response.json().await?;
        Ok(token_data["access_token"]
            .as_str()
            .unwrap_or_default()
            .to_string())
    } else {
        Err(format!("Failed to get admin token: {}", response.status()).into())
    }
}
