"""End-to-end tests for the Pharos pipeline with a mocked LLM."""

from __future__ import annotations

import io
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

import core.pipeline as pipeline_module
import registry.registry_builder as registry_builder
from core.pipeline import CVScorer, PharosPipeline


@dataclass
class DummyCVScorer:
    """Fixed-score CV scorer used for deterministic pipeline tests."""

    cv_risk: float = 5.0

    def score_image(self, image_bytes: bytes | None) -> dict[str, Any]:
        """Return deterministic layer outputs for tests."""
        return {
            "color_uniformity": 5.0,
            "print_sharpness": 5.0,
            "brightness_consistency": 5.0,
            "cv_risk_contribution": self.cv_risk,
        }


class MockLLM:
    """Minimal mock of llama.cpp chat API returning predefined JSON."""

    def __init__(self, payload: dict[str, Any]) -> None:
        self._payload = payload

    def create_chat_completion(self, **_: Any) -> dict[str, Any]:
        """Return a response object with JSON content."""
        return {"choices": [{"message": {"content": json.dumps(self._payload)}}]}


def make_image_bytes(size: tuple[int, int] = (320, 240)) -> bytes:
    """Create a simple in-memory JPEG image for tests."""
    image = Image.new("RGB", size, color=(200, 220, 230))
    buf = io.BytesIO()
    image.save(buf, format="JPEG")
    return buf.getvalue()


@pytest.fixture()
def fresh_registry(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Build a fresh temporary registry and patch all readers to use it."""
    registry_path = tmp_path / "pharos_registry.db"
    monkeypatch.setattr(registry_builder, "REGISTRY_PATH", registry_path)
    monkeypatch.setattr(pipeline_module, "REGISTRY_PATH", registry_path)
    registry_builder.build_registry()
    return registry_path


def test_authentic_pack_scores_low_risk(fresh_registry: Path) -> None:
    """Authentic-like output and valid batch format should remain low risk."""
    print("Checking authentic pack path: valid format + low model risk should stay LOW.")
    payload = {
        "medicine_name": "Amoxicillin",
        "batch_code": {
            "extracted": "AMX1234ABC",
            "format_valid": True,
            "format_error": None,
            "registry_match": None,
        },
        "expiry_date": {"extracted": "06/2027", "format_valid": True, "not_expired": True},
        "manufacturer": {"extracted": "GlaxoSmithKline", "region_inferred": "EU", "name_legible": True},
        "security": {"hologram_detected": True, "hologram_intact": True, "tamper_evident_seal": True, "seal_intact": True},
        "visual_anomalies": [],
        "risk_score": 10,
        "risk_level": "LOW",
        "flags": [],
        "confidence": 0.95,
        "analysis_notes": "Looks authentic.",
        "image_quality_ok": True,
    }
    pipeline = PharosPipeline(MockLLM(payload), cv_scorer=DummyCVScorer(cv_risk=5.0))
    result = pipeline.analyse(make_image_bytes(), location="0.1,36.8")
    assert result["final"]["risk_level"] == "LOW"


def test_batch_code_error_sets_batch_format_flag(fresh_registry: Path) -> None:
    """Invalid batch code format must generate BATCH_FORMAT_INVALID flag."""
    print("Checking batch format error path: invalid format must set BATCH_FORMAT_INVALID.")
    payload = {
        "medicine_name": "Amoxicillin",
        "batch_code": {
            "extracted": "ABC",
            "format_valid": False,
            "format_error": "Too short",
            "registry_match": None,
        },
        "expiry_date": {"extracted": "06/2027", "format_valid": True, "not_expired": True},
        "manufacturer": {"extracted": "Unknown", "region_inferred": "Unknown", "name_legible": True},
        "security": {"hologram_detected": True, "hologram_intact": True, "tamper_evident_seal": True, "seal_intact": True},
        "visual_anomalies": [],
        "risk_score": 35,
        "risk_level": "MODERATE",
        "flags": [],
        "confidence": 0.8,
        "analysis_notes": "Format mismatch.",
        "image_quality_ok": True,
    }
    pipeline = PharosPipeline(MockLLM(payload), cv_scorer=DummyCVScorer(cv_risk=5.0))
    result = pipeline.analyse(make_image_bytes(), location=None)
    assert "BATCH_FORMAT_INVALID" in result["final"]["flags"]


def test_who_alert_batch_forces_critical_risk(fresh_registry: Path) -> None:
    """Known WHO alert batch codes should force CRITICAL risk."""
    print("Checking WHO alert override: known alert code should force CRITICAL.")
    payload = {
        "medicine_name": "Artemether/Lumefantrine",
        "batch_code": {
            "extracted": "FAKE-BATCH-99",
            "format_valid": False,
            "format_error": "Known bad code",
            "registry_match": False,
        },
        "expiry_date": {"extracted": "12/2027", "format_valid": True, "not_expired": True},
        "manufacturer": {"extracted": "Unknown", "region_inferred": "Unknown", "name_legible": True},
        "security": {"hologram_detected": True, "hologram_intact": False, "tamper_evident_seal": True, "seal_intact": True},
        "visual_anomalies": [],
        "risk_score": 10,
        "risk_level": "LOW",
        "flags": [],
        "confidence": 0.9,
        "analysis_notes": "Possible counterfeit.",
        "image_quality_ok": True,
    }
    pipeline = PharosPipeline(MockLLM(payload), cv_scorer=DummyCVScorer(cv_risk=10.0))
    result = pipeline.analyse(make_image_bytes(), location=None)
    assert result["final"]["risk_level"] == "CRITICAL"


def test_blurry_image_sets_image_quality_false(fresh_registry: Path) -> None:
    """Model-indicated low image quality should surface in final output."""
    print("Checking blurry-image handling: image_quality_ok should remain False.")
    payload = {
        "medicine_name": None,
        "batch_code": {"extracted": None, "format_valid": None, "format_error": "Too blurry", "registry_match": None},
        "expiry_date": {"extracted": None, "format_valid": None, "not_expired": None},
        "manufacturer": {"extracted": None, "region_inferred": None, "name_legible": False},
        "security": {"hologram_detected": None, "hologram_intact": None, "tamper_evident_seal": None, "seal_intact": None},
        "visual_anomalies": [],
        "risk_score": 50,
        "risk_level": "MODERATE",
        "flags": ["IMAGE_QUALITY_INSUFFICIENT"],
        "confidence": 0.2,
        "analysis_notes": "Image too blurry.",
        "image_quality_ok": False,
    }
    pipeline = PharosPipeline(MockLLM(payload), cv_scorer=DummyCVScorer(cv_risk=85.0))
    result = pipeline.analyse(make_image_bytes(), location=None)
    assert result["final"]["image_quality_ok"] is False


def test_none_image_is_handled_gracefully(fresh_registry: Path) -> None:
    """Pipeline should return a safe result when image bytes are missing."""
    print("Checking null image handling: pipeline should not crash on None input.")
    pipeline = PharosPipeline(MockLLM({}), cv_scorer=CVScorer())
    result = pipeline.analyse(None, location=None)
    assert result["final"]["risk_level"] in {"LOW", "MODERATE", "HIGH", "CRITICAL"}
    assert result["final"]["image_quality_ok"] is False
