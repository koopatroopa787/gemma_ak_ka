"""Unit tests for the OpenCV scorer."""

from __future__ import annotations

import cv2
import numpy as np

from core.pipeline import CVScorer


def _encode_jpeg(image: np.ndarray) -> bytes:
    """Encode a numpy image as JPEG bytes."""
    ok, buf = cv2.imencode(".jpg", image)
    if not ok:
        raise RuntimeError("Failed to encode test image")
    return buf.tobytes()


def test_uniform_colour_has_low_color_uniformity_score() -> None:
    """Uniform image should not be flagged as color-shifted."""
    print("Checking uniform colour: expected low color_uniformity score.")
    scorer = CVScorer()
    image = np.full((256, 256, 3), 128, dtype=np.uint8)
    scores = scorer.score_image(_encode_jpeg(image))
    assert scores["color_uniformity"] < 30


def test_shifted_colour_has_high_color_uniformity_score() -> None:
    """High saturation variance should produce a high color shift score."""
    print("Checking shifted colour: expected high color_uniformity score.")
    scorer = CVScorer()
    image = np.zeros((256, 256, 3), dtype=np.uint8)
    image[:, :128] = (0, 0, 255)      # saturated red
    image[:, 128:] = (120, 120, 120)  # near-grey
    scores = scorer.score_image(_encode_jpeg(image))
    assert scores["color_uniformity"] > 60


def test_sharp_text_has_low_print_sharpness_score() -> None:
    """High edge variance text should map to a low suspiciousness score."""
    print("Checking sharp text: expected low print_sharpness score.")
    scorer = CVScorer()
    image = np.full((256, 512, 3), 255, dtype=np.uint8)
    cv2.putText(image, "AMX1234", (30, 150), cv2.FONT_HERSHEY_SIMPLEX, 2.5, (0, 0, 0), 5, cv2.LINE_AA)
    scores = scorer.score_image(_encode_jpeg(image))
    assert scores["print_sharpness"] < 20


def test_blurred_image_has_high_print_sharpness_score() -> None:
    """Blurred text should map to a high suspiciousness sharpness score."""
    print("Checking blurred image: expected high print_sharpness score.")
    scorer = CVScorer()
    image = np.full((256, 512, 3), 255, dtype=np.uint8)
    cv2.putText(image, "AMX1234", (30, 150), cv2.FONT_HERSHEY_SIMPLEX, 2.5, (0, 0, 0), 5, cv2.LINE_AA)
    blurred = cv2.GaussianBlur(image, (25, 25), 0)
    scores = scorer.score_image(_encode_jpeg(blurred))
    assert scores["print_sharpness"] > 70
