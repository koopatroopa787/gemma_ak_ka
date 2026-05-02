"""
pharos/core/pipeline.py
────────────────────────
The main Pharos inference pipeline.

One call: image_bytes → structured risk report

Architecture:
  1. Gemma 4 E2B (vision): OCR + structured JSON extraction
  2. OpenCV layer:          colour histogram + edge sharpness scoring
  3. Registry checker:      batch code validation + counterfeit alert lookup
  4. Risk scorer:           weighted ensemble → final 0–100 score

Each layer is independent and testable. If Gemma fails, OpenCV
still runs. If the registry is unavailable, the model score stands.

This separation is what you show in your write-up as "hybrid pipeline."
"""

from __future__ import annotations

import base64
import time
from typing import Optional

import cv2
import numpy as np

from core.prompt import SYSTEM_PROMPT, parse_model_output
from core.schema import RiskLevel
from registry.registry_builder import REGISTRY_PATH, check_batch_code

# ── OpenCV scoring layer ───────────────────────────────────────────────────────

class CVScorer:
    """
    Classical computer vision checks that complement Gemma 4's output.

    These are FAST (sub-100ms) and don't require a GPU.
    They score the things a general-purpose VLM can't reliably do:
    - Colour histogram consistency
    - Print edge sharpness
    """

    def score_image(self, image_bytes: Optional[bytes]) -> dict:
        """
        Returns a dict of CV scores, each 0–100 (higher = more suspicious).
        """
        if not image_bytes:
            return {"cv_error": "No image bytes provided", "cv_risk_contribution": 0}

        nparr  = np.frombuffer(image_bytes, np.uint8)
        img_cv = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img_cv is None:
            return {"cv_error": "Could not decode image", "cv_risk_contribution": 0}

        scores = {}
        scores["color_uniformity"] = self._score_color_uniformity(img_cv)
        scores["print_sharpness"]  = self._score_print_sharpness(img_cv)
        scores["brightness_consistency"] = self._score_brightness_consistency(img_cv)

        # Weight and combine into CV risk contribution (0–100)
        cv_risk = (
            scores["color_uniformity"]       * 0.40 +
            scores["print_sharpness"]        * 0.40 +
            scores["brightness_consistency"] * 0.20
        )
        scores["cv_risk_contribution"] = round(cv_risk, 1)
        return scores

    def _score_color_uniformity(self, img: np.ndarray) -> float:
        """
        High variance in colour histogram can indicate re-printing.
        Returns 0 (uniform/authentic) to 100 (suspicious).
        """
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        s_channel = hsv[:, :, 1].flatten()

        # High saturation std is suspicious (ink colour inconsistency)
        sat_std = float(np.std(s_channel))
        # Normalise: typical authentic pack std is 30–60; suspicious > 80
        score = min(100, max(0, (sat_std - 40) * 2.0))
        return round(score, 1)

    def _score_print_sharpness(self, img: np.ndarray) -> float:
        """
        Laplacian variance measures edge sharpness. Low variance = blur = suspicious.
        Returns 0 (sharp/authentic) to 100 (blurry/suspicious).
        """
        grey      = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        laplacian = cv2.Laplacian(grey, cv2.CV_64F)
        variance  = laplacian.var()

        # Typical print: variance > 400. Below 100 is very blurry.
        score = max(0, min(100, 100 - (variance / 4.0)))
        return round(score, 1)

    def _score_brightness_consistency(self, img: np.ndarray) -> float:
        """
        Checks for uneven brightness patches that suggest different print runs.
        Divides image into quadrants and measures luminosity deviation.
        """
        grey = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(float)
        h, w = grey.shape
        mid_h, mid_w = h // 2, w // 2

        quadrants = [
            grey[:mid_h, :mid_w],
            grey[:mid_h, mid_w:],
            grey[mid_h:, :mid_w],
            grey[mid_h:, mid_w:],
        ]
        means = [float(q.mean()) for q in quadrants]
        deviation = float(np.std(means))

        # Std deviation > 20 brightness units across quadrants is suspicious
        score = min(100, deviation * 3.0)
        return round(score, 1)


# ── Risk scoring ───────────────────────────────────────────────────────────────

def compute_final_risk(
    gemma_risk:    int,
    cv_risk:       float,
    registry_result: dict,
    gemma_confidence: float
) -> tuple[int, RiskLevel, list[str]]:
    """
    Combine Gemma 4, OpenCV, and registry signals into a final risk score.

    Weights:
    - Registry alert (CRITICAL): overrides everything → score 95
    - Gemma 4 output: 50% weight (scaled by confidence)
    - CV scores: 30% weight
    - Registry format check: 20% weight
    """
    flags = []
    base_score = 0.0

    # Registry: counterfeit alert — this is ground truth, not a model output
    if registry_result.get("in_counterfeit_alert"):
        alert = registry_result.get("alert_details", {})
        flags.append(f"KNOWN_ALERT_{alert.get('alert_id', 'UNKNOWN')}")
        # If severity is CRITICAL, force high score regardless of model
        if alert.get("severity") == "CRITICAL":
            return 95, RiskLevel.CRITICAL, flags
        else:
            base_score = max(base_score, 75.0)
            flags.append("WHO_ALERT")

    # Registry: batch code format check
    if registry_result.get("format_valid") is False:
        base_score += 20.0 * 0.20
        flags.append("BATCH_FORMAT_INVALID")
    elif registry_result.get("format_valid") is True:
        base_score -= 5.0  # small bonus for verified format
        flags.append("BATCH_FORMAT_VERIFIED")

    # Gemma 4 contribution (scaled by confidence)
    effective_gemma = gemma_risk * gemma_confidence
    base_score += effective_gemma * 0.50

    # OpenCV contribution
    base_score += cv_risk * 0.30

    final_score = int(min(100, max(0, base_score)))

    if final_score >= 85:
        level = RiskLevel.CRITICAL
    elif final_score >= 66:
        level = RiskLevel.HIGH
    elif final_score >= 31:
        level = RiskLevel.MODERATE
    else:
        level = RiskLevel.LOW

    return final_score, level, flags


# ── Main pipeline ──────────────────────────────────────────────────────────────

class PharosPipeline:
    """
    Full Pharos inference pipeline.
    Initialise once, call analyse() for each image.
    """

    def __init__(self, llm, cv_scorer: Optional[CVScorer] = None):
        self.llm      = llm
        self.cv       = cv_scorer or CVScorer()
        self.registry = REGISTRY_PATH.exists()
        if not self.registry:
            print("⚠️  Registry not found. Run `python registry/registry_builder.py --build` first.")

    def analyse(self, image_bytes: Optional[bytes], location: Optional[str] = None) -> dict:
        """
        Full analysis of a blister pack image.

        Args:
            image_bytes: Raw image bytes from camera
            location:    Optional GPS location string for evidence record

        Returns:
            Complete analysis result including all layer outputs and metadata
        """
        t_start = time.perf_counter()

        result = {
            "timestamp":    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "location":     location,
            "layers":       {},
            "final":        {},
            "latency_ms":   0,
        }

        # ── Layer 1: Gemma 4 vision inference ─────────────────────────────────
        t1 = time.perf_counter()
        gemma_raw   = self._run_gemma(image_bytes)
        gemma_parse = parse_model_output(gemma_raw) if gemma_raw else None
        result["layers"]["gemma"] = {
            "raw_output":     gemma_raw,
            "parsed":         gemma_parse,
            "latency_ms":     round((time.perf_counter() - t1) * 1000),
            "parse_success":  gemma_parse is not None,
        }

        # ── Layer 2: OpenCV scoring ────────────────────────────────────────────
        t2 = time.perf_counter()
        cv_scores = self.cv.score_image(image_bytes)
        result["layers"]["opencv"] = {
            "scores":     cv_scores,
            "latency_ms": round((time.perf_counter() - t2) * 1000),
        }

        # ── Layer 3: Registry check ────────────────────────────────────────────
        registry_result = {}
        if self.registry and gemma_parse:
            batch_info  = gemma_parse.get("batch_code", {}) or {}
            batch_code  = batch_info.get("extracted")
            medicine    = gemma_parse.get("medicine_name")
            if batch_code:
                registry_result = check_batch_code(batch_code, medicine)
        result["layers"]["registry"] = registry_result

        # ── Layer 4: Risk scoring ──────────────────────────────────────────────
        gemma_risk   = (gemma_parse or {}).get("risk_score", 50)
        gemma_conf   = (gemma_parse or {}).get("confidence", 0.5)
        cv_risk      = cv_scores.get("cv_risk_contribution", 0)

        final_score, final_level, flags = compute_final_risk(
            gemma_risk, cv_risk, registry_result, gemma_conf
        )

        # Merge Gemma flags with our computed flags
        gemma_flags = (gemma_parse or {}).get("flags", [])
        all_flags   = list(set(flags + gemma_flags))

        result["final"] = {
            "risk_score":     final_score,
            "risk_level":     final_level.value,
            "flags":          all_flags,
            "medicine_name":  (gemma_parse or {}).get("medicine_name"),
            "batch_code":     ((gemma_parse or {}).get("batch_code") or {}).get("extracted"),
            "expiry_date":    ((gemma_parse or {}).get("expiry_date") or {}).get("extracted"),
            "analysis_notes": (gemma_parse or {}).get("analysis_notes"),
            "image_quality_ok": (
                (gemma_parse or {}).get("image_quality_ok")
                if (gemma_parse or {}).get("image_quality_ok") is not None
                else bool(image_bytes)
            ),
        }

        result["latency_ms"] = round((time.perf_counter() - t_start) * 1000)
        return result

    def _run_gemma(self, image_bytes: Optional[bytes]) -> str | None:
        """Run Gemma 4 inference. Returns raw string output."""
        try:
            if not image_bytes:
                return None
            b64 = base64.b64encode(image_bytes).decode("utf-8")
            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                        {"type": "text", "text": "Analyse this blister pack and return JSON."}
                    ]
                }
            ]
            response = self.llm.create_chat_completion(
                messages=messages,
                max_tokens=1024,
                temperature=0.1,
                response_format={"type": "json_object"},
            )
            return response["choices"][0]["message"]["content"]
        except Exception as e:
            print(f"[GEMMA ERROR] {e}")
            return None
