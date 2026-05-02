# Pharos

**Offline pharmaceutical packaging verification for pharmacists in low-resource settings.**

Pharos helps pharmacists in areas with unreliable internet detect potentially counterfeit medicine packaging using on-device AI. It runs entirely on a mid-range Android device — no internet connection required.

> ⚠️ **Research prototype.** Pharos is a decision-support tool that assists pharmacist judgment. It is not a validated medical device and does not replace professional verification procedures. See [LIMITATIONS.md](LIMITATIONS.md).

---

## Demo

[Watch the 3-minute demo →](#)  
[Live demo →](#)  
[Kaggle write-up →](#)

---

## Architecture

```
Camera image
      │
      ▼
┌─────────────────────────────────────────────────┐
│  Layer 1: Gemma 4 E2B (on-device, INT4 GGUF)   │
│  • OCR: batch code, expiry date, manufacturer   │
│  • Structured JSON output (schema-constrained)  │
│  • Anomaly flags from visual inspection         │
└───────────────────┬─────────────────────────────┘
                    │
      ┌─────────────┼──────────────┐
      ▼             ▼              ▼
┌──────────┐ ┌──────────┐  ┌──────────────┐
│ Layer 2  │ │ Layer 3  │  │  Layer 3b    │
│ OpenCV   │ │ Registry │  │ Alert check  │
│ colour   │ │ batch    │  │ WHO MPA      │
│ + edges  │ │ format   │  │ known codes  │
└────┬─────┘ └────┬─────┘  └──────┬───────┘
     └────────────┴───────────────┘
                  │
                  ▼
         ┌────────────────┐
         │  Risk Scorer   │
         │  Weighted      │
         │  ensemble      │
         │  0–100 + flags │
         └────────┬───────┘
                  │
                  ▼
         Pharmacist result
         (risk level + flags
          + plain-English note)
```

**What each layer does and why:**

- **Gemma 4 E2B** handles OCR and structured information extraction — tasks it demonstrably excels at. It does *not* try to detect millimetre-level print registration errors, which exceed its reliable capability ceiling.
- **OpenCV** handles the metrology Gemma cannot do reliably: colour histogram consistency, print edge sharpness, brightness uniformity across the pack surface.
- **Registry** provides ground truth: known counterfeit batch codes from WHO Medical Product Alerts, and batch code format validation per manufacturer.
- **Risk scorer** weights all three signals into a final 0–100 score. A registry alert overrides the model output — this is intentional.

---

## Benchmarks

> Measured on [device name] — [date]

| Model | Quantisation | End-to-end latency | RAM (peak) | JSON parse rate |
|---|---|---|---|---|
| Gemma 4 E2B | INT4 (Q4_K_M) | [X]s | [X]MB | [X]/10 |

Run the benchmark yourself:
```bash
python benchmark.py --image data/authentic/sample_pack.jpg
```

---

## Getting Started

### Requirements
- Python 3.10+
- Android device with 4GB+ RAM (for mobile deployment)
- llama.cpp with vision support

### Install
```bash
git clone https://github.com/[your-repo]/pharos
cd pharos
pip install -r requirements.txt

# Download model (2.5GB)
# Get gemma-4-E2B-it-Q4_K_M.gguf from:
# https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF
mkdir models && mv gemma-4-E2B-it-Q4_K_M.gguf models/
```

### Build the registry
```bash
python registry/registry_builder.py --build
```

### Run benchmark on your hardware
```bash
python benchmark.py --image path/to/your/blister_pack.jpg
```

### Test the pipeline
```bash
python tests/test_pipeline.py
```

### Generate dataset from your authentic pack photos
```bash
# Put your photos in data/authentic/
python data/defect_generator.py --input data/authentic/ --output data/dataset/ --per-image 5
```

---

## Fine-tuning (Unsloth)

See `unsloth_finetune.ipynb` for the complete Kaggle-compatible fine-tuning notebook.

Pre-trained adapter weights: [HuggingFace link]  
Training dataset: [Kaggle dataset link]  
Benchmark results: `benchmark_results_e2b.json`

**Fine-tuning decision:** We first tested Gemma 4 E2B in zero-shot configuration on 15 real blister pack photos. [Result: X% batch code accuracy]. [We then fine-tuned / zero-shot was sufficient]. See `LIMITATIONS.md` for full rationale.

---

## Repository Structure

```
pharos/
├── core/
│   ├── schema.py           # Pydantic schema — the contract for all outputs
│   ├── prompt.py           # System prompt + few-shot builder
│   └── pipeline.py         # Main inference pipeline (Gemma + CV + Registry)
├── data/
│   └── defect_generator.py # Dataset augmentation from real photos
├── registry/
│   └── registry_builder.py # SQLite medicine registry + WHO alert data
├── deploy/
│   └── flutter/            # Mobile app (Flutter + Cactus)
├── tests/
│   └── test_pipeline.py    # End-to-end test on sample packs
├── benchmark.py            # Latency + accuracy benchmark
├── benchmark_results_e2b.json  # Our measured results
├── unsloth_finetune.ipynb  # Fine-tuning notebook (Kaggle-ready)
├── LIMITATIONS.md          # Honest capability assessment
└── README.md
```

---

## Tracks

- **Health & Sciences** — Decision support tool for pharmacists in low-resource settings
- **Cactus** — Local-first mobile deployment via llama.cpp on Android
- **Unsloth** — Fine-tuned Gemma 4 E2B adapter for pharmaceutical OCR
