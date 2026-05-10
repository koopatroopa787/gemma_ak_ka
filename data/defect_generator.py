"""
pharos/data/defect_generator.py
────────────────────────────────
Takes real blister pack photos (shot on Day 1) and generates
"suspicious" variants by applying programmatic defects.

Key principle: defects are applied to REAL photos, not synthetic renders.
This avoids the uncanny valley problem — your model trains on authentic
packaging with specific, controlled anomalies.

Defect types mirror real-world counterfeiting patterns:
  - Batch code format errors (most common counterfeit tell)
  - Colour shift (cheaper inks)
  - Print blur (lower DPI printing)
  - Font substitution (approximated via text overlay)
  - Hologram degradation (blur/mask)

Usage:
    python data/defect_generator.py --input data/authentic/ --output data/suspicious/
    python data/defect_generator.py --input data/authentic/ --output data/suspicious/ --per-image 5

Dependencies:
    pip install Pillow numpy
"""

import argparse
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

# ── Defect parameters ──────────────────────────────────────────────────────────

DEFECT_REGISTRY = {
    "color_shift": {
        "description": "Saturation or hue shift — cheaper inks",
        "severity_range": (0.05, 0.25),   # fraction of shift
    },
    "print_blur": {
        "description": "Gaussian blur on text regions — lower DPI printing",
        "radius_range": (0.5, 2.5),
    },
    "batch_code_overlay": {
        "description": "Replace batch code text with invalid format",
        "invalid_formats": [
            "XXXXXX",          # too short, no structure
            "00000000",        # all zeros
            "FAKE-BATCH-99",   # obviously wrong format
            "ABC",             # too short
            "123456789012345", # too long
        ]
    },
    "brightness_inconsistency": {
        "description": "Uneven brightness — different print runs",
        "region_fraction": (0.15, 0.4),   # what fraction of image to darken/lighten
        "intensity_range": (0.6, 0.85),
    },
    "hologram_degradation": {
        "description": "Blur/grey-out a region that may be the hologram",
        "region_fraction": (0.05, 0.15),
    },
}


# ── Individual defect functions ────────────────────────────────────────────────

def apply_color_shift(img: Image.Image, severity: float) -> Image.Image:
    """Shift saturation by severity fraction. Simulates cheaper inks."""
    enhancer = ImageEnhance.Color(img)
    factor = 1.0 + (severity if random.random() > 0.5 else -severity)
    return enhancer.enhance(max(0.3, factor))


def apply_print_blur(img: Image.Image, radius: float) -> Image.Image:
    """Gaussian blur — simulates lower DPI printing or worn print plates."""
    return img.filter(ImageFilter.GaussianBlur(radius=radius))


def apply_brightness_patch(img: Image.Image, region_frac: float, intensity: float) -> Image.Image:
    """Darken a random rectangular region — simulates uneven ink coverage."""
    arr = np.array(img).astype(float)
    h, w = arr.shape[:2]

    patch_h = int(h * region_frac)
    patch_w = int(w * region_frac)
    y0 = random.randint(0, h - patch_h)
    x0 = random.randint(0, w - patch_w)

    arr[y0:y0+patch_h, x0:x0+patch_w] *= intensity
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)


def apply_hologram_degradation(img: Image.Image, region_frac: float) -> Image.Image:
    """
    Blur and desaturate a region where a hologram might be.
    Simulates a copied/printed hologram rather than a genuine one.
    """
    arr = np.array(img)
    h, w = arr.shape[:2]

    # Place in a plausible hologram location (upper right or lower right)
    ph = int(h * region_frac)
    pw = int(w * region_frac)
    y0 = random.choice([0, h - ph])
    x0 = w - pw - random.randint(0, pw // 2)

    # Extract region, desaturate and blur, paste back
    region = Image.fromarray(arr[y0:y0+ph, x0:x0+pw])
    region = ImageEnhance.Color(region).enhance(0.1)  # nearly greyscale
    region = region.filter(ImageFilter.GaussianBlur(radius=2))
    result = img.copy()
    result.paste(region, (x0, y0))
    return result


def apply_batch_code_error(img: Image.Image, invalid_formats: list[str]) -> tuple[Image.Image, str]:
    """
    Overlays an invalid batch code string over where a batch code likely appears.
    This is a text overlay — it won't look perfect but is readable by the model.
    Returns the modified image and the fake code used.
    """
    fake_code = random.choice(invalid_formats)
    draw = ImageDraw.Draw(img.copy())
    w, h = img.size

    # Batch codes typically appear in the lower third of the pack
    x = random.randint(int(w * 0.05), int(w * 0.4))
    y = random.randint(int(h * 0.55), int(h * 0.75))

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size=max(12, h // 30))
    except Exception:
        font = ImageFont.load_default()

    # Draw white background behind text for readability
    bbox = draw.textbbox((x, y), fake_code, font=font)
    draw.rectangle(bbox, fill="white")
    draw.text((x, y), fake_code, fill="black", font=font)

    return draw._image, fake_code


# ── Composite defect application ───────────────────────────────────────────────

DEFECT_COMBINATIONS = [
    # (defect_types, expected_anomalies_for_label, risk_score_range)
    (["color_shift"],                          ["color_shift"],                       (15, 35)),
    (["print_blur"],                           ["print_blur"],                        (10, 30)),
    (["batch_code_error"],                     ["batch_code_format"],                 (55, 75)),
    (["hologram_degradation"],                 ["hologram_anomaly"],                  (40, 60)),
    (["color_shift", "print_blur"],            ["color_shift", "print_blur"],         (25, 50)),
    (["batch_code_error", "color_shift"],      ["batch_code_format", "color_shift"],  (60, 80)),
    (["batch_code_error", "hologram_degradation"], ["batch_code_format", "hologram_anomaly"], (70, 90)),
]


def apply_defects(img: Image.Image, defect_types: list[str]) -> tuple[Image.Image, dict]:
    """Apply a combination of defects and return modified image + metadata."""
    params = DEFECT_REGISTRY
    result = img.copy()
    applied = []
    fake_batch_code = None

    for defect in defect_types:
        if defect == "color_shift":
            severity = random.uniform(*params["color_shift"]["severity_range"])
            result = apply_color_shift(result, severity)
            applied.append({"type": "color_shift", "severity": round(severity, 3)})

        elif defect == "print_blur":
            radius = random.uniform(*params["print_blur"]["radius_range"])
            result = apply_print_blur(result, radius)
            applied.append({"type": "print_blur", "radius": round(radius, 2)})

        elif defect == "batch_code_error":
            result, fake_batch_code = apply_batch_code_error(
                result, params["batch_code_overlay"]["invalid_formats"]
            )
            applied.append({"type": "batch_code_format", "fake_code": fake_batch_code})

        elif defect == "brightness_inconsistency":
            frac = random.uniform(*params["brightness_inconsistency"]["region_fraction"])
            intensity = random.uniform(*params["brightness_inconsistency"]["intensity_range"])
            result = apply_brightness_patch(result, frac, intensity)
            applied.append({"type": "brightness_inconsistency", "intensity": round(intensity, 2)})

        elif defect == "hologram_degradation":
            frac = random.uniform(*params["hologram_degradation"]["region_fraction"])
            result = apply_hologram_degradation(result, frac)
            applied.append({"type": "hologram_anomaly"})

    return result, {"defects_applied": applied, "fake_batch_code": fake_batch_code}


# ── Dataset generation ─────────────────────────────────────────────────────────

def generate_dataset(
    input_dir: str,
    output_dir: str,
    suspicious_per_image: int = 5,
    seed: int = 42
) -> dict:
    """
    For each authentic image in input_dir:
      - Copy it to output_dir/authentic/ with label authentic=True
      - Generate suspicious_per_image variants with different defect combos

    Returns a summary dict with dataset stats.
    """
    random.seed(seed)
    np.random.seed(seed)

    input_path  = Path(input_dir)
    output_path = Path(output_dir)
    auth_dir    = output_path / "authentic"
    susp_dir    = output_path / "suspicious"
    auth_dir.mkdir(parents=True, exist_ok=True)
    susp_dir.mkdir(parents=True, exist_ok=True)

    image_files = list(input_path.glob("*.jpg")) + list(input_path.glob("*.jpeg")) + list(input_path.glob("*.png"))
    if not image_files:
        print(f"❌ No images found in {input_dir}")
        return {}

    labels = []
    n_authentic = 0
    n_suspicious = 0

    for img_path in image_files:
        print(f"Processing {img_path.name}...")
        img = Image.open(img_path).convert("RGB")

        # Copy authentic
        auth_name = f"auth_{img_path.stem}.jpg"
        img.save(auth_dir / auth_name, quality=95)
        labels.append({
            "filename":   f"authentic/{auth_name}",
            "authentic":  True,
            "risk_level": "LOW",
            "defects":    [],
            "source":     img_path.name
        })
        n_authentic += 1

        # Generate suspicious variants
        combos = random.sample(DEFECT_COMBINATIONS, min(suspicious_per_image, len(DEFECT_COMBINATIONS)))
        for i, (defect_types, anomaly_types, risk_range) in enumerate(combos):
            susp_img, metadata = apply_defects(img, defect_types)
            susp_name = f"susp_{img_path.stem}_{i:02d}.jpg"
            susp_img.save(susp_dir / susp_name, quality=95)

            risk_score = random.randint(*risk_range)
            risk_level = (
                "HIGH"     if risk_score >= 66 else
                "MODERATE" if risk_score >= 31 else
                "LOW"
            )
            labels.append({
                "filename":      f"suspicious/{susp_name}",
                "authentic":     False,
                "risk_level":    risk_level,
                "risk_score":    risk_score,
                "defects":       metadata["defects_applied"],
                "anomaly_types": anomaly_types,
                "source":        img_path.name
            })
            n_suspicious += 1

    # Save labels
    labels_path = output_path / "labels.json"
    with open(labels_path, "w") as f:
        json.dump(labels, f, indent=2)

    summary = {
        "total":       n_authentic + n_suspicious,
        "authentic":   n_authentic,
        "suspicious":  n_suspicious,
        "labels_file": str(labels_path),
        "output_dir":  str(output_path),
    }

    print(f"\n[OK] Dataset generated:")
    print(f"   Authentic:  {n_authentic}")
    print(f"   Suspicious: {n_suspicious}")
    print(f"   Total:      {n_authentic + n_suspicious}")
    print(f"   Labels:     {labels_path}")
    return summary


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate suspicious blister pack variants from authentic photos")
    parser.add_argument("--input",      required=True, help="Directory containing authentic blister pack photos")
    parser.add_argument("--output",     required=True, help="Output directory for dataset")
    parser.add_argument("--per-image",  type=int, default=5, help="Number of suspicious variants per authentic image (default: 5)")
    parser.add_argument("--seed",       type=int, default=42, help="Random seed for reproducibility")
    args = parser.parse_args()

    summary = generate_dataset(args.input, args.output, args.per_image, args.seed)
    print(f"\nRun 'python benchmark.py --image {args.input}/[any_image.jpg]' next.")
