use axum::{
    async_trait,
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    response::IntoResponse,
    Json,
};
use axum_extra::{
    headers::{authorization::Bearer, Authorization},
    TypedHeader,
};
use jsonwebtoken::{decode, decode_header, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// --- THESE `use` STATEMENTS ARE NOW CORRECTED ---
use crate::models::CreateTask;
use crate::db;
use crate::AppState;
// --------------------------------------------

// This struct represents the claims we expect in our JWT.
// The `sub` (subject) field is the user's ID from Keycloak.
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
}

// This struct will hold the authenticated user's ID after successful validation.
pub struct AuthenticatedUser {
    pub id: Uuid,
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
        // Get the Authorization header containing the Bearer token using the extractor.
        let TypedHeader(Authorization(bearer)) = 
            TypedHeader::<Authorization<Bearer>>::from_request_parts(parts, state)
            .await
            .map_err(|_| (StatusCode::UNAUTHORIZED, "Missing or invalid Authorization header"))?;

        // Find the specific key that was used to sign this token from cached JWKS.
        let header = decode_header(bearer.token())
            .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid token header"))?;
        let kid = header.kid.ok_or((StatusCode::BAD_REQUEST, "Token missing 'kid' (Key ID) in header"))?;
        let decoding_key: &DecodingKey = state
            .jwks
            .get(&kid)
            .ok_or((StatusCode::UNAUTHORIZED, "Signing key not found in JWKS cache"))?;
        
        let mut validation = Validation::new(jsonwebtoken::Algorithm::RS256);
        validation.validate_aud = false; // For this simple case, we'll skip audience validation.

        let token_data = decode::<Claims>(bearer.token(), decoding_key, &validation)
            .map_err(|_| (StatusCode::UNAUTHORIZED, "Token validation failed"))?;

        // 5. The 'sub' claim from the token is the user's ID. Parse it into a UUID.
        let user_id = Uuid::parse_str(&token_data.claims.sub)
            .map_err(|_| (StatusCode::UNAUTHORIZED, "Invalid user ID ('sub') in token"))?;

        Ok(AuthenticatedUser { id: user_id })
    }
}

// The handlers are now much cleaner and more secure. They just take AuthenticatedUser as a parameter.
// If the token is invalid, this code will never even be reached.
pub async fn create_task_handler(
    State(state): State<AppState>,
    user: AuthenticatedUser, // The extractor provides the authenticated user's ID
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
    user: AuthenticatedUser, // The extractor provides the user
) -> impl IntoResponse {
    match db::get_tasks_for_user(&state.db_pool, user.id).await {
        Ok(tasks) => (StatusCode::OK, Json(tasks)).into_response(),
        Err(e) => {
            eprintln!("Failed to get tasks: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, "Failed to get tasks.").into_response()
        }
    }
}