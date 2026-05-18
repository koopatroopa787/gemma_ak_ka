# Pharos — On-Device Medicine Verification

**Detect counterfeit pharmaceutical packaging with Gemma 4 — fully offline, on your Android phone.**

Pharos helps pharmacists and patients in areas with unreliable internet verify medicine authenticity in seconds. Point the camera at a blister pack, tap Analyze, and get a risk score with tamper evidence, batch code validation, and manufacturer recognition — all running locally on a mid-range Android device.

> ⚠️ **Research prototype.** Pharos is a decision-support tool that assists pharmacist judgment. It is not a validated medical device and does not replace professional verification procedures. See [LIMITATIONS.md](LIMITATIONS.md).

---

## Demo

https://github.com/user-attachments/assets/placeholder

*Scanning a Cipla AZEE-500 blister pack — full analysis in under 60 s on CPU.*

---

## How it works

```
Camera (full-screen capture UI)
        │
        ▼
┌───────────────────────────────────────────────┐
│  Gemma 4 E2B Vision  (on-device, LiteRT-LM)  │
│  • OCR: medicine name, batch code, expiry     │
│  • Seal & tamper-evidence assessment          │
│  • Hologram / security feature detection      │
│  • Structured JSON output (schema-enforced)   │
└──────────────────────┬────────────────────────┘
                       │
           ┌───────────┴───────────┐
           ▼                       ▼
   ┌──────────────┐       ┌─────────────────┐
   │  Post-process │       │  Risk Scorer    │
   │  OCR typo fix │       │  0–100 + flags  │
   │  Seal default │       │  LOW / MODERATE │
   │  Score adjust │       │  HIGH / CRITICAL│
   └──────┬───────┘       └────────┬────────┘
          └───────────┬────────────┘
                      ▼
             Local SQLite store
             Ed25519 signed record
                      │
              (optional, async)
                      ▼
             pharos-sync.onrender.com
             batch upload when online
```

### Why LiteRT-LM?

Gemma 4 is a **vision** model — it reads the image, not just text. Running it with Google's LiteRT-LM runtime (the same runtime powering AI Edge Gallery) gives:

- Native GPU acceleration (Adreno / Mali) with automatic CPU fallback
- Image input via `Content.ImageBytes` — no base64, no JPEG artefacts
- Streaming tokens via `MessageCallback` — the result appears token-by-token

---

## Repo structure

```
pharos/
├── core/
│   ├── schema.py                   # Pydantic output schema
│   ├── prompt.py                   # System prompt builder
│   └── pipeline.py                 # Python inference pipeline (server-side)
├── data/
│   ├── defect_generator.py         # Synthetic defect augmentation
│   └── PHOTOGRAPHY_GUIDE.md        # How to photograph blister packs
├── registry/
│   └── registry_builder.py         # Medicine registry + WHO alert data
├── server/
│   ├── main.py                     # FastAPI sync server (optional)
│   └── dashboard.html              # Admin dashboard
├── deploy/
│   └── flutter/                    # Android app (Flutter + LiteRT-LM)
│       ├── lib/
│       │   ├── screens/
│       │   │   ├── scanner_screen.dart    # Main scan UI
│       │   │   ├── capture_screen.dart    # Full-screen camera capture
│       │   │   ├── result_screen.dart     # Risk result display
│       │   │   └── history_screen.dart    # Local scan history
│       │   └── services/
│       │       ├── pharos_vision_service.dart  # Flutter↔Kotlin bridge
│       │       ├── model_manager.dart          # Model download + validation
│       │       ├── db_service.dart             # Local SQLite
│       │       └── signing_service.dart        # Ed25519 record signing
│       └── android/app/src/main/kotlin/
│           └── com/pharos/pharos_flutter/
│               ├── MainActivity.kt         # MethodChannel + EventChannel
│               └── PharosLiteRTModule.kt   # LiteRT-LM engine wrapper
├── frontend/                       # Stitch-generated web dashboard (optional)
├── tests/                          # Python pipeline tests
├── benchmark.py                    # Latency + accuracy benchmark
├── pharos_finetune_fixed_final.ipynb  # Unsloth fine-tune notebook
├── render.yaml                     # Render.com deploy config
├── requirements.txt
└── README.md
```

---

## Flutter app — getting started

### Prerequisites

| Requirement | Version |
|---|---|
| Flutter | 3.27+ |
| Android SDK | API 26+ (Android 8) |
| Kotlin Gradle Plugin | 2.3.0 |
| JDK | 17 |

### Build

```bash
cd deploy/flutter
flutter pub get
flutter run                    # debug on connected device
flutter build apk --release    # release APK
```

### First launch

1. The app asks to download the Gemma 4 E2B model (~2.6 GB) over Wi-Fi.  
   Download happens once; all subsequent scans are fully offline.
2. Alternatively, if you have the file already (e.g. from AI Edge Gallery):  
   tap **Select existing file from device** and point to `gemma-4-E2B-it.litertlm`.

**Model source:** [`litert-community/gemma-4-E2B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) on HuggingFace (no auth required).

### Scan flow

```
Tap "Analyze Medicine"
        │
        ▼
Full-screen camera opens          ← engine loads in background here
        │  frame the blister pack
        ▼
Tap shutter → Review photo
        │  "Use Photo" or "Retake"
        ▼
Vision analysis (30–120 s CPU / ~15 s GPU)
        │
        ▼
Risk result screen
```

### Architecture notes (Android)

- **`PharosLiteRTModule.kt`** — wraps the LiteRT-LM `Engine` / `Conversation` lifecycle.  
  Handles GPU→CPU fallback, JPEG→PNG conversion, conversation reset between scans, and streaming tokens via `MessageCallback`.
- **`MainActivity.kt`** — exposes a `MethodChannel` (commands) and `EventChannel` (streaming tokens) to Flutter.
- **`pharos_vision_service.dart`** — assembles tokens from the event stream and resolves a `Future<String>` with the complete JSON.

---

## Python pipeline (optional backend)

The `core/` + `server/` modules provide an optional FastAPI server you can run on a machine with a GPU for faster batch verification or an admin dashboard.

```bash
pip install -r requirements.txt

# Build the medicine registry
python registry/registry_builder.py --build

# Run the server
uvicorn server.main:app --reload

# Or run a single-image benchmark
python benchmark.py --image path/to/blister_pack.jpg
```

---

## Fine-tuning

`pharos_finetune_fixed_final.ipynb` is a Kaggle-compatible Unsloth notebook that fine-tunes Gemma 4 E2B on a pharmaceutical OCR dataset.

To run it:
1. Open in Kaggle (T4 GPU, ~45 min)
2. Set `HF_TOKEN` secret with write access to your HuggingFace repo
3. Outputs a LoRA adapter pushed to HuggingFace

---

## Risk levels

| Level | Score | Meaning |
|---|---|---|
| **LOW** | 0–30 | Packaging consistent with authentic product |
| **MODERATE** | 31–65 | One or more minor anomalies — manual review recommended |
| **HIGH** | 66–84 | Multiple red flags — do not dispense without further checks |
| **CRITICAL** | 85–100 | Clear counterfeiting evidence or known-bad batch |

---

## Tracks

| Track | How Pharos qualifies |
|---|---|
| **Health & Sciences** | Decision-support for pharmacists in low-resource settings |
| **Google — LiteRT / AI Edge** | On-device inference via LiteRT-LM 0.11.0, same runtime as AI Edge Gallery |
| **Unsloth** | Gemma 4 E2B fine-tuned with Unsloth on pharmaceutical OCR data |

---

## Limitations

See [LIMITATIONS.md](LIMITATIONS.md) for an honest assessment of what Pharos can and cannot do.

Key points:
- Inference quality depends on image clarity — good lighting is essential
- OCR accuracy on low-contrast foil printing is imperfect; post-processing rules correct common errors
- The model has not been validated against a statistically representative sample of counterfeit medicines
- CPU inference takes 30–120 s on mid-range devices; GPU path requires a compatible Adreno/Mali driver

---

## Contributing

Issues and PRs welcome. Please open an issue before starting large changes.

---

*Built for the Google × Kaggle Gemma 3 Hackathon 2025.*
