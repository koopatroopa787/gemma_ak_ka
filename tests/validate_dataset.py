"""Dataset quality validator for Pharos image and label data."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

# Histogram correlation threshold for "nearly identical" photos.
HISTOGRAM_SIMILARITY_THRESHOLD = 0.98
# If one visual cluster exceeds this ratio, dataset diversity is too low.
MAX_CLUSTER_DOMINANCE_RATIO = 0.60
# Acceptable authentic/suspicious split range.
MIN_CLASS_RATIO = 0.40
MAX_CLASS_RATIO = 0.60
# Images below this Laplacian variance are considered too blurry for training.
MIN_SHARPNESS_SCORE = 20.0

# Full schema fields used when labels contain model-ready JSON.
REQUIRED_SCHEMA_FIELDS = {
    "medicine_name",
    "batch_code",
    "expiry_date",
    "manufacturer",
    "security",
    "visual_anomalies",
    "risk_score",
    "risk_level",
    "flags",
    "confidence",
    "analysis_notes",
    "image_quality_ok",
}

# Metadata fields used by defect_generator labels.
REQUIRED_METADATA_FIELDS = {"filename", "authentic", "risk_level"}


@dataclass
class CheckResult:
    """Structured result of a single validation check."""

    passed: bool
    summary: str
    recommendation: str | None = None


def load_labels(dataset_dir: Path) -> list[dict[str, Any]]:
    """Load labels.json from dataset directory."""
    labels_path = dataset_dir / "labels.json"
    if not labels_path.exists():
        raise FileNotFoundError(f"labels.json not found in {dataset_dir}")
    with labels_path.open("r", encoding="utf-8") as handle:
        labels = json.load(handle)
    if not isinstance(labels, list):
        raise ValueError("labels.json must contain a list of label objects")
    return labels


def collect_images(dataset_dir: Path) -> list[Path]:
    """Collect image files under the dataset directory."""
    patterns = ("*.jpg", "*.jpeg", "*.png")
    files: list[Path] = []
    for pattern in patterns:
        files.extend(dataset_dir.rglob(pattern))
    return sorted(files)


def histogram_vector(image_path: Path) -> np.ndarray:
    """Build a normalized HSV histogram feature vector."""
    image = cv2.imread(str(image_path))
    if image is None:
        raise ValueError(f"Unable to read image: {image_path}")
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    hist = cv2.calcHist([hsv], [0, 1, 2], None, [8, 8, 8], [0, 180, 0, 256, 0, 256])
    hist = cv2.normalize(hist, hist).flatten().astype(np.float32)
    return hist


def check_image_diversity(images: list[Path]) -> CheckResult:
    """Cluster images by histogram similarity and report over-dominant clusters."""
    if not images:
        return CheckResult(False, "No images found.", "Add image files to the dataset path.")

    centroids: list[np.ndarray] = []
    cluster_counts: list[int] = []
    for image_path in images:
        vec = histogram_vector(image_path)
        assigned = False
        for idx, centroid in enumerate(centroids):
            similarity = float(cv2.compareHist(vec, centroid, cv2.HISTCMP_CORREL))
            if similarity >= HISTOGRAM_SIMILARITY_THRESHOLD:
                cluster_counts[idx] += 1
                centroids[idx] = (centroid * (cluster_counts[idx] - 1) + vec) / cluster_counts[idx]
                assigned = True
                break
        if not assigned:
            centroids.append(vec)
            cluster_counts.append(1)

    largest_cluster = max(cluster_counts)
    ratio = largest_cluster / len(images)
    if ratio > MAX_CLUSTER_DOMINANCE_RATIO:
        return CheckResult(
            False,
            f"Image diversity failed: largest visual cluster is {ratio:.1%} of dataset.",
            "Reshoot with wider angles/lighting so no cluster exceeds 60% near-identical images.",
        )
    return CheckResult(True, f"Image diversity passed: largest cluster ratio {ratio:.1%}.")


def check_label_completeness(labels: list[dict[str, Any]]) -> CheckResult:
    """Validate that labels include required fields for their detected format."""
    if not labels:
        return CheckResult(False, "Label completeness failed: labels.json is empty.", "Generate labels first.")

    schema_mode = any("label_json" in item for item in labels)
    required = REQUIRED_SCHEMA_FIELDS if schema_mode else REQUIRED_METADATA_FIELDS
    missing_examples: list[str] = []

    for index, item in enumerate(labels):
        target = item.get("label_json", item)
        missing = sorted(required - set(target.keys()))
        if missing:
            missing_examples.append(f"item {index}: {', '.join(missing)}")
        if len(missing_examples) >= 5:
            break

    if missing_examples:
        return CheckResult(
            False,
            "Label completeness failed.",
            "Add missing fields in labels.json. Examples: " + " | ".join(missing_examples),
        )
    mode_label = "schema labels" if schema_mode else "metadata labels"
    return CheckResult(True, f"Label completeness passed for {mode_label}.")


def check_class_balance(labels: list[dict[str, Any]]) -> CheckResult:
    """Validate authentic vs suspicious distribution within target bounds."""
    authentic = sum(1 for item in labels if bool(item.get("authentic", False)))
    suspicious = sum(1 for item in labels if not bool(item.get("authentic", False)))
    total = authentic + suspicious
    if total == 0:
        return CheckResult(False, "Class balance failed: no class labels found.", "Populate 'authentic' values.")

    authentic_ratio = authentic / total
    if MIN_CLASS_RATIO <= authentic_ratio <= MAX_CLASS_RATIO:
        return CheckResult(
            True,
            f"Class balance passed: authentic={authentic} suspicious={suspicious} ({authentic_ratio:.1%} authentic).",
        )
    return CheckResult(
        False,
        f"Class balance failed: authentic={authentic} suspicious={suspicious} ({authentic_ratio:.1%} authentic).",
        "Adjust generation counts to target 40–60% authentic share.",
    )


def check_image_quality(images: list[Path]) -> CheckResult:
    """Flag images with low sharpness score."""
    blurry: list[str] = []
    for image_path in images:
        image = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
        if image is None:
            blurry.append(f"{image_path.name} (unreadable)")
            continue
        score = float(cv2.Laplacian(image, cv2.CV_64F).var())
        if score < MIN_SHARPNESS_SCORE:
            blurry.append(f"{image_path.name} ({score:.1f})")

    if blurry:
        preview = ", ".join(blurry[:10])
        return CheckResult(
            False,
            f"Image quality failed: {len(blurry)} images below sharpness threshold {MIN_SHARPNESS_SCORE}.",
            f"Retake blurry images. Examples: {preview}",
        )
    return CheckResult(True, "Image quality passed: no blurry images below threshold.")


def print_report(results: dict[str, CheckResult]) -> bool:
    """Print pass/fail summary and return overall success state."""
    print("=" * 72)
    print("PHAROS DATASET VALIDATION REPORT")
    print("=" * 72)
    overall_pass = True
    for name, result in results.items():
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {name}: {result.summary}")
        if result.recommendation:
            print(f"       Recommendation: {result.recommendation}")
        overall_pass = overall_pass and result.passed
    print("-" * 72)
    print("OVERALL:", "PASS" if overall_pass else "FAIL")
    print("=" * 72)
    return overall_pass


def main() -> int:
    """CLI entrypoint for dataset validation."""
    parser = argparse.ArgumentParser(description="Validate quality of a Pharos training dataset.")
    parser.add_argument("--dataset", required=True, help="Path to dataset root (contains images + labels.json).")
    args = parser.parse_args()

    dataset_dir = Path(args.dataset)
    if not dataset_dir.exists():
        print(f"Dataset path does not exist: {dataset_dir}")
        return 1

    try:
        labels = load_labels(dataset_dir)
        images = collect_images(dataset_dir)
        checks = {
            "Image diversity": check_image_diversity(images),
            "Label completeness": check_label_completeness(labels),
            "Class balance": check_class_balance(labels),
            "Image quality": check_image_quality(images),
        }
        passed = print_report(checks)
        return 0 if passed else 1
    except Exception as exc:
        print(f"Validation failed with error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
