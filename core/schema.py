"""
pharos/core/schema.py
────────────────────
The single source of truth for what Gemma 4 must output.
Every other module in Pharos depends on this schema.

Design principles:
- Every field is Optional with a default — a partial parse is better than a crash
- Severity and risk levels are enums — no free-text strings that drift
- The schema is self-documenting — field descriptions become prompt examples
"""

from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field

# ── Enums ──────────────────────────────────────────────────────────────────────

class RiskLevel(str, Enum):
    LOW      = "LOW"       # 0–30:  proceed with normal dispensing
    MODERATE = "MODERATE"  # 31–65: verify with registry, flag for pharmacist
    HIGH     = "HIGH"      # 66–84: do not dispense, quarantine pack
    CRITICAL = "CRITICAL"  # 85–100: known counterfeit batch — alert authority


class Severity(str, Enum):
    LOW      = "low"
    MODERATE = "moderate"
    HIGH     = "high"


class AnomalyType(str, Enum):
    COLOR_SHIFT        = "color_shift"         # saturation/hue deviation
    PRINT_BLUR         = "print_blur"          # text edges not sharp
    FONT_MISMATCH      = "font_mismatch"       # different typeface detected
    BATCH_CODE_FORMAT  = "batch_code_format"   # doesn't match manufacturer pattern
    EXPIRY_FORMAT      = "expiry_format"       # wrong date format for region
    MISSING_TEXT       = "missing_text"        # required field absent
    HOLOGRAM_ANOMALY   = "hologram_anomaly"    # hologram incomplete/absent
    SEAL_BROKEN        = "seal_broken"         # tamper seal compromised
    LABEL_INCONSISTENCY= "label_inconsistency" # medicine name vs strength mismatch


# ── Sub-models ─────────────────────────────────────────────────────────────────

class BatchCode(BaseModel):
    extracted:    Optional[str]  = Field(None, description="The exact text of the batch code as it appears on the pack")
    format_valid: Optional[bool] = Field(None, description="Whether the batch code matches the expected format for this manufacturer")
    format_error: Optional[str]  = Field(None, description="If invalid, describe what is wrong with the format")
    registry_match: Optional[bool] = Field(None, description="Whether the batch code was found in the WHO medicines registry")


class ExpiryDate(BaseModel):
    extracted:    Optional[str]  = Field(None, description="The exact expiry text as it appears e.g. '12/2026' or 'EXP DEC 2026'")
    format_valid: Optional[bool] = Field(None, description="Whether the format matches WHO standard date formats")
    not_expired:  Optional[bool] = Field(None, description="True if the medicine has not yet expired based on today's date")


class Manufacturer(BaseModel):
    extracted:       Optional[str] = Field(None, description="The manufacturer name as printed on the pack")
    region_inferred: Optional[str] = Field(None, description="Inferred region e.g. 'EU', 'India', 'Sub-Saharan Africa', 'Unknown'")
    name_legible:    Optional[bool] = Field(None, description="Whether the manufacturer name is clearly readable")


class SecurityFeatures(BaseModel):
    hologram_detected:    Optional[bool] = Field(None, description="Whether a hologram or foil security feature is visible")
    hologram_intact:      Optional[bool] = Field(None, description="Whether the hologram appears complete and undamaged")
    tamper_evident_seal:  Optional[bool] = Field(None, description="Whether a tamper-evident seal is present")
    seal_intact:          Optional[bool] = Field(None, description="Whether the seal appears unbroken")


class VisualAnomaly(BaseModel):
    anomaly_type: AnomalyType
    severity:     Severity
    region:       Optional[str] = Field(None, description="Where on the pack e.g. 'batch_code_area', 'hologram', 'full_label'")
    description:  str           = Field(..., description="One clear sentence describing what was observed")


# ── Root output schema ─────────────────────────────────────────────────────────

class BlistPackAnalysis(BaseModel):
    """
    Complete analysis output for one blister pack scan.
    This is what Gemma 4 must return as JSON, and what the OpenCV
    layer and registry checker augment before risk scoring.
    """

    # Core extracted fields
    medicine_name:  Optional[str]          = Field(None, description="The medicine name and strength as printed e.g. 'Amoxicillin 500mg'")
    batch_code:     Optional[BatchCode]    = None
    expiry_date:    Optional[ExpiryDate]   = None
    manufacturer:   Optional[Manufacturer] = None
    security:       Optional[SecurityFeatures] = None

    # Visual anomalies detected by Gemma 4
    visual_anomalies: list[VisualAnomaly] = Field(
        default_factory=list,
        description="List of specific visual anomalies observed. Empty list if none found."
    )

    # Risk assessment
    risk_score: int = Field(
        ...,
        ge=0, le=100,
        description="0=definitely authentic, 100=definitely counterfeit"
    )
    risk_level:  RiskLevel = Field(..., description="Categorical risk level derived from score")
    flags:       list[str] = Field(
        default_factory=list,
        description="Short human-readable flags for the pharmacist UI e.g. ['BATCH_INVALID', 'KNOWN_ALERT']"
    )

    # Model self-assessment
    confidence:       float        = Field(..., ge=0.0, le=1.0, description="Model confidence in this analysis 0.0–1.0")
    analysis_notes:   Optional[str] = Field(None, description="One or two sentences explaining the overall assessment in plain English")
    image_quality_ok: Optional[bool] = Field(None, description="Whether the image was clear enough for reliable analysis")


# ── Prompt schema export ───────────────────────────────────────────────────────

SCHEMA_JSON = BlistPackAnalysis.model_json_schema()

# Human-readable field list for prompt injection
REQUIRED_FIELDS_PROMPT = """
You must return a JSON object with exactly these fields:
- medicine_name: string (name and strength as printed)
- batch_code: {extracted, format_valid, format_error, registry_match}
- expiry_date: {extracted, format_valid, not_expired}
- manufacturer: {extracted, region_inferred, name_legible}
- security: {hologram_detected, hologram_intact, tamper_evident_seal, seal_intact}
- visual_anomalies: list of {anomaly_type, severity, region, description}
  anomaly_type must be one of: color_shift, print_blur, font_mismatch,
  batch_code_format, expiry_format, missing_text, hologram_anomaly,
  seal_broken, label_inconsistency
- risk_score: integer 0–100
- risk_level: one of LOW / MODERATE / HIGH / CRITICAL
- flags: list of short strings for pharmacist
- confidence: float 0.0–1.0
- analysis_notes: plain English summary (1–2 sentences)
- image_quality_ok: boolean
"""


if __name__ == "__main__":
    # Quick validation test
    import json
    sample = BlistPackAnalysis(
        medicine_name="Amoxicillin 500mg",
        batch_code=BatchCode(
            extracted="AMX-2024-091-X",
            format_valid=True,
            registry_match=True
        ),
        expiry_date=ExpiryDate(
            extracted="06/2026",
            format_valid=True,
            not_expired=True
        ),
        manufacturer=Manufacturer(
            extracted="GlaxoSmithKline Ltd",
            region_inferred="EU",
            name_legible=True
        ),
        security=SecurityFeatures(
            hologram_detected=True,
            hologram_intact=True,
            tamper_evident_seal=True,
            seal_intact=True
        ),
        visual_anomalies=[],
        risk_score=8,
        risk_level=RiskLevel.LOW,
        flags=[],
        confidence=0.94,
        analysis_notes="Packaging appears fully consistent with authentic product. All security features present and intact.",
        image_quality_ok=True
    )
    print(json.dumps(sample.model_dump(), indent=2))
    print("\n✅ Schema validation passed")
