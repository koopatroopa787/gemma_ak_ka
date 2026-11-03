"""Unit tests for the offline registry helpers."""

from __future__ import annotations

from pathlib import Path

import pytest

import registry.registry_builder as registry_builder


@pytest.fixture()
def fresh_registry(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Build a new registry database for each test run."""
    path = tmp_path / "pharos_registry.db"
    monkeypatch.setattr(registry_builder, "REGISTRY_PATH", path)
    registry_builder.build_registry()
    return path


def test_known_alert_code_is_flagged(fresh_registry: Path) -> None:
    """Known WHO alert batch code should return in_counterfeit_alert=True."""
    print("Checking known alert code lookup in registry.")
    result = registry_builder.check_batch_code("FAKE-BATCH-99", "Artemether/Lumefantrine")
    assert result["in_counterfeit_alert"] is True


def test_valid_gsk_batch_format_is_true(fresh_registry: Path) -> None:
    """GSK-like Amoxicillin format should validate."""
    print("Checking valid GSK batch code format validation.")
    result = registry_builder.check_batch_code("AMX1234ABC", "Amoxicillin")
    assert result["format_valid"] is True


def test_medicine_label_with_strength_uses_registry_format(fresh_registry: Path) -> None:
    """A full package label should still find its registry medicine."""
    result = registry_builder.check_batch_code("AMX1234ABC", "Amoxicillin 500mg")
    assert result["format_valid"] is True


def test_garbage_batch_string_is_invalid(fresh_registry: Path) -> None:
    """Garbage batch codes should fail format validation."""
    print("Checking garbage batch code handling.")
    result = registry_builder.check_batch_code("!!!", "Amoxicillin")
    assert result["format_valid"] is False


def test_get_medicine_info_returns_who_id(fresh_registry: Path) -> None:
    """Medicine info lookup should include a WHO identifier."""
    print("Checking medicine lookup returns WHO ID.")
    result = registry_builder.get_medicine_info("Amoxicillin")
    assert isinstance(result, dict)
    assert "who_id" in result
