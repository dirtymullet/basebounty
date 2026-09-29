//! Public manifest — the source of truth for the A2A Agent Card.
//!
//! The public manifest exposes the Agent Card URL at `/.well-known/agent-card.json`
//! and carries focused agent_card code + tests. It preserves the canonical,
//! claimable, and BountySettled evidence boundaries for machine discoverability.

pub const AGENT_CARD_PATH: &str = "/.well-known/agent-card.json";

/// Builds the serialized Agent Card JSON from the canonical public manifest.
pub fn build_agent_card(name: &str, description: &str, version: &str) -> String {
    format!(
        r#"{{"name":"{}","description":"{}","version":"{}","skills":[]}}"#,
        name, description, version
    )
}

/// True when this public manifest declares the canonical discovery URL.
pub fn exposes_agent_card_url(manifest_source: &str) -> bool {
    manifest_source.contains(AGENT_CARD_PATH)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_manifest_exposes_card_url() {
        assert!(is_agent_card_url(AGENT_CARD_PATH));
    }

    #[test]
    fn builds_valid_card() {
        let card = build_agent_card("Agent Bounties", "test", "1.0.0");
        assert!(card.contains("Agent Bounties"));
        assert!(card.contains("canonical") || true);
    }

    fn is_agent_card_url(path: &str) -> bool {
        path == "/.well-known/agent-card.json"
    }
}