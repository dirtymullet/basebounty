#!/usr/bin/env python3
"""A2A Agent Card smoke checker.

Validates that the Agent Card fixture and its serving contract are internally
consistent. Exit code 0 means the smoke passes; non-zero prints the failure.
Run from the workspace root (WORKSPACE_ROOT) exactly like the immutable check.
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("WORKSPACE_ROOT", "/workspace"))


def read(path: str) -> str:
    candidate = ROOT / path
    if not candidate.is_file():
        raise SystemExit(f"missing required file: {path}")
    return candidate.read_text(encoding="utf-8")


def main() -> int:
    fixture = json.loads(read("fixtures/a2a-agent-card.json"))

    # identity
    if fixture.get("name") != "Agent Bounties":
        raise SystemExit("card name != Agent Bounties")
    if not fixture.get("description") or not fixture.get("version"):
        raise SystemExit("description/version required")

    # interfaces are canonical A2A 1.0 on the documented binding
    binding = "https://agentbounties.app/docs/a2a-direct-api-binding-v1"
    for it in fixture.get("supportedInterfaces", []):
        if not str(it.get("url", "")).startswith("https://api.agentbounties.app/"):
            raise SystemExit("interface url not canonical API")
        if it.get("protocolVersion") != "1.0":
            raise SystemExit("interface must be A2A 1.0")
        if it.get("protocolBinding") != binding:
            raise SystemExit("interface must declare the documented binding")

    # skills + evidence boundary
    ids = {str(s.get("id", "")) for s in fixture.get("skills", [])}
    required = {
        "discover-funded-work",
        "plan-bounty-claim",
        "submit-bounty-evidence",
        "check-bounty-settlement",
        "post-bounty",
    }
    if required - ids:
        raise SystemExit(f"missing skills: {sorted(required - ids)}")

    serialized = json.dumps(fixture, sort_keys=True).lower()
    if any(bad in serialized for bad in ("private_key", "seed phrase", "api_key", "secret")):
        raise SystemExit("forbidden material detected")
    for phrase in ("canonical", "claimable", "bountysettled"):
        if phrase not in serialized:
            raise SystemExit(f"missing evidence-boundary phrase: {phrase}")

    # cache headers documented
    api = read("crates/api/src/main.rs").lower()
    if "etag" not in api or "cache-control" not in api:
        raise SystemExit("api must implement ETag and Cache-Control")

    print("A2A Agent Card smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())