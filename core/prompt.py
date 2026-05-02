"""
pharos/core/prompt.py
─────────────────────
Builds the system prompt and few-shot examples for Gemma 4 E2B.

This is the FIRST thing you test on Day 2. Before any fine-tuning,
before any OpenCV, run this against 3 real blister pack photos and
measure:
  1. Does it return valid JSON every time?
  2. Does it extract the batch code correctly?
  3. Does the risk score make intuitive sense?

If yes to all three on authentic packs → zero-shot is sufficient.
If batch codes are wrong >20% → fine-tune.
"""

from __future__ import annotations

from core.schema import REQUIRED_FIELDS_PROMPT

# ── System prompt ──────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are Pharos, an expert pharmaceutical packaging analyst.
Your sole purpose is to help pharmacists in low-resource settings detect
potentially counterfeit or substandard medicine packaging.

IMPORTANT CONTEXT:
- You are assisting a trained pharmacist. You are NOT making a medical decision.
- Your output is one input into their judgment, not a replacement for it.
- When uncertain, report what you observe factually and set confidence lower.
- False positives (flagging authentic medicine) are costly. Be precise.

YOUR TASK:
Analyse the pharmaceutical blister pack in the image. Examine:
1. All printed text: batch code, expiry date, medicine name, strength, manufacturer
2. Print quality: sharpness, consistent colour, proper alignment
3. Security features: hologram, tamper seal, anti-counterfeit markings
4. Overall consistency: does everything match what you'd expect from this type of pack?

BATCH CODE FORMAT KNOWLEDGE:
- EU packs: typically alphanumeric 8–12 chars, often contains manufacturing site code
- Indian generic manufacturers: often format XXXNN-YYYYMM or similar
- African regional packs: often follow WHO prequalification batch numbering
- If format is clearly wrong for the apparent manufacturer region, flag it

OUTPUT RULES:
- Respond ONLY with a valid JSON object. No preamble, no explanation outside JSON.
- Do not wrap in markdown code blocks.
- If a field cannot be determined from the image, use null.
- If image quality prevents analysis, set image_quality_ok: false and risk_score: 50.
""" + REQUIRED_FIELDS_PROMPT


# ── Few-shot examples (inject into user turn as image+text pairs) ──────────────

# These are text descriptions used when building the prompt.
# In the actual inference call, replace with real image bytes.

FEW_SHOT_DESCRIPTIONS = [
    {
        "description": "Authentic amoxicillin blister pack, clear text, intact hologram",
        "expected_output": {
            "medicine_name": "Amoxicillin 500mg",
            "batch_code": {
                "extracted": "AMX-2024-091-X",
                "format_valid": True,
                "format_error": None,
                "registry_match": None
            },
            "expiry_date": {
                "extracted": "06/2026",
                "format_valid": True,
                "not_expired": True
            },
            "manufacturer": {
                "extracted": "GlaxoSmithKline Ltd",
                "region_inferred": "EU",
                "name_legible": True
            },
            "security": {
                "hologram_detected": True,
                "hologram_intact": True,
                "tamper_evident_seal": True,
                "seal_intact": True
            },
            "visual_anomalies": [],
            "risk_score": 5,
            "risk_level": "LOW",
            "flags": [],
            "confidence": 0.93,
            "analysis_notes": "Packaging fully consistent with authentic GSK product. All security features present.",
            "image_quality_ok": True
        }
    },
    {
        "description": "Suspicious artemether pack — batch code format wrong for claimed manufacturer, slight colour shift on label",
        "expected_output": {
            "medicine_name": "Artemether 20mg/Lumefantrine 120mg",
            "batch_code": {
                "extracted": "ATM12345",
                "format_valid": False,
                "format_error": "Format 'ATM12345' does not match Novartis standard alphanumeric format for this product line",
                "registry_match": None
            },
            "expiry_date": {
                "extracted": "03/2025",
                "format_valid": True,
                "not_expired": False
            },
            "manufacturer": {
                "extracted": "Novartis AG",
                "region_inferred": "EU",
                "name_legible": True
            },
            "security": {
                "hologram_detected": True,
                "hologram_intact": False,
                "tamper_evident_seal": True,
                "seal_intact": True
            },
            "visual_anomalies": [
                {
                    "anomaly_type": "batch_code_format",
                    "severity": "high",
                    "region": "batch_code_area",
                    "description": "Batch code 'ATM12345' uses non-standard format inconsistent with Novartis packaging conventions"
                },
                {
                    "anomaly_type": "color_shift",
                    "severity": "low",
                    "region": "full_label",
                    "description": "Label background shows slight cyan shift compared to reference Coartem packaging"
                }
            ],
            "risk_score": 72,
            "risk_level": "HIGH",
            "flags": ["BATCH_FORMAT_INVALID", "EXPIRED", "HOLOGRAM_DAMAGED", "COLOR_ANOMALY"],
            "confidence": 0.81,
            "analysis_notes": "Multiple inconsistencies detected. Batch code format mismatch is the primary concern. Do not dispense pending verification.",
            "image_quality_ok": True
        }
    },
    {
        "description": "Poor quality photo — blurry, low light, pack partially out of frame",
        "expected_output": {
            "medicine_name": None,
            "batch_code": {
                "extracted": None,
                "format_valid": None,
                "format_error": "Cannot read — image too blurry",
                "registry_match": None
            },
            "expiry_date": {
                "extracted": None,
                "format_valid": None,
                "not_expired": None
            },
            "manufacturer": {
                "extracted": None,
                "region_inferred": None,
                "name_legible": False
            },
            "security": {
                "hologram_detected": None,
                "hologram_intact": None,
                "tamper_evident_seal": None,
                "seal_intact": None
            },
            "visual_anomalies": [],
            "risk_score": 50,
            "risk_level": "MODERATE",
            "flags": ["IMAGE_QUALITY_INSUFFICIENT"],
            "confidence": 0.20,
            "analysis_notes": "Image quality insufficient for reliable analysis. Please retake photo in good lighting with the full pack in frame.",
            "image_quality_ok": False
        }
    }
]


# ── Inference wrapper ──────────────────────────────────────────────────────────

def build_user_message(image_bytes: bytes) -> list[dict]:
    """
    Build the message payload for Gemma 4 E2B vision inference.
    Image goes BEFORE the text instruction per Unsloth's recommendation.

    Args:
        image_bytes: Raw JPEG/PNG bytes from camera capture

    Returns:
        List of message dicts for the model's messages parameter
    """
    import base64
    b64 = base64.b64encode(image_bytes).decode("utf-8")

    return [
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{b64}"}
                },
                {
                    "type": "text",
                    "text": "Analyse this pharmaceutical blister pack and return your assessment as a JSON object."
                }
            ]
        }
    ]


def parse_model_output(raw_output: str) -> dict | None:
    """
    Parse and validate model output. Returns None if unparseable.
    Strips markdown fences if the model adds them despite instructions.
    """
    import json

    from core.schema import BlistPackAnalysis

    text = raw_output.strip()

    # Strip markdown code fences if present
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    if text.endswith("```"):
        text = text[:-3].strip()

    try:
        raw = json.loads(text)
        validated = BlistPackAnalysis(**raw)
        return validated.model_dump()
    except json.JSONDecodeError as e:
        print(f"[PARSE ERROR] Invalid JSON: {e}")
        return None
    except Exception as e:
        print(f"[VALIDATION ERROR] Schema mismatch: {e}")
        # Return raw dict even if schema validation fails — partial data is useful
        try:
            return json.loads(text)
        except Exception:
            return None


if __name__ == "__main__":
    # Print the system prompt so you can inspect it before Day 2 testing
    print("=" * 60)
    print("PHAROS SYSTEM PROMPT")
    print("=" * 60)
    print(SYSTEM_PROMPT)
    print(f"\nPrompt length: {len(SYSTEM_PROMPT)} characters")
    print(f"Few-shot examples: {len(FEW_SHOT_DESCRIPTIONS)}")
