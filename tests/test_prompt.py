"""Tests for prompt helpers."""

from __future__ import annotations

import base64
import json

from core.prompt import build_user_message, parse_model_output


def test_build_user_message_places_image_before_text() -> None:
    """Gemma message format should include image token before instruction text."""
    print("Checking multimodal message ordering: image should come before text.")
    fake_bytes = b"fake-image-bytes"
    message = build_user_message(fake_bytes)
    content = message[0]["content"]
    assert content[0]["type"] == "image_url"
    assert content[1]["type"] == "text"
    encoded = content[0]["image_url"]["url"].split(",")[1]
    assert encoded == base64.b64encode(fake_bytes).decode("utf-8")


def test_parse_model_output_accepts_fenced_json() -> None:
    """Parser should strip markdown fences and return validated dict."""
    print("Checking JSON parser robustness with markdown-fenced payload.")
    payload = {
        "medicine_name": "Amoxicillin",
        "batch_code": {"extracted": "AMX1234ABC", "format_valid": True, "format_error": None, "registry_match": None},
        "expiry_date": {"extracted": "06/2027", "format_valid": True, "not_expired": True},
        "manufacturer": {"extracted": "GSK", "region_inferred": "EU", "name_legible": True},
        "security": {"hologram_detected": True, "hologram_intact": True, "tamper_evident_seal": True, "seal_intact": True},
        "visual_anomalies": [],
        "risk_score": 10,
        "risk_level": "LOW",
        "flags": [],
        "confidence": 0.95,
        "analysis_notes": "Looks authentic.",
        "image_quality_ok": True,
    }
    raw = "```json\n" + json.dumps(payload) + "\n```"
    parsed = parse_model_output(raw)
    assert parsed is not None
    assert parsed["risk_level"] == "LOW"
