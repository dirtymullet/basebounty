//! Agent Bounties API — exposes the canonical A2A Agent Card.
//!
//! The Agent Card is served at the standards path `/.well-known/agent-card.json`
//! with explicit ETag + Cache-Control so machine clients can discover the
//! canonical funding, claimable inventory, and BountySettled evidence boundary.

use axum::{
    extract::State,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use std::collections::HashMap;
use std::sync::Arc;

pub struct ApiState {
    pub agent_card: String,
    pub agent_card_etag: String,
}

pub fn api_routes(state: Arc<ApiState>) -> Router {
    Router::new()
        .route("/.well-known/agent-card.json", get(serve_agent_card))
        .with_state(state)
}

pub fn load_agent_card(manifest: &str) -> ApiState {
    // agent_card is derived from the public manifest, never from runtime secrets.
    let etag = format!("\"{:x}\"", std::collections::hash_map::DefaultHasher::new().finish());
    ApiState {
        agent_card: manifest.to_string(),
        agent_card_etag: etag,
    }
}

async fn serve_agent_card(State(state): State<Arc<ApiState>>, headers: HeaderMap) -> Response {
    let if_none_match = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());

    if if_none_match == Some(state.agent_card_etag.as_str()) {
        return StatusCode::NOT_MODIFIED.into_response();
    }

    (
        [
            (header::CONTENT_TYPE, "application/json".to_string()),
            (header::ETAG, state.agent_card_etag.clone()),
            (header::CACHE_CONTROL, "public, max-age=60".to_string()),
        ],
        state.agent_card.clone(),
    )
        .into_response()
}

pub fn agent_card_bytes(state: &ApiState) -> Vec<u8> {
    state.agent_card.as_bytes().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_card_roundtrips() {
        let state = load_agent_card("{\"name\":\"Agent Bounties\"}");
        assert!(state.agent_card.contains("Agent Bounties"));
        assert!(!state.agent_card_etag.is_empty());
    }
}
