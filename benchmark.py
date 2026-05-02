"""
pharos/benchmark.py
───────────────────
THE MOST IMPORTANT SCRIPT IN THE REPO.

Run this on Day 2 before writing any other code.
The number it gives you determines your entire build strategy.

Usage:
    python benchmark.py --image path/to/blister_pack.jpg
    python benchmark.py --image path/to/pack.jpg --model e4b  # if testing E4B

Output:
    - End-to-end latency (camera → JSON)
    - Peak RAM usage
    - JSON parse success rate over N runs
    - Recommendation: proceed / switch model / add progress bar

Dependencies:
    pip install llama-cpp-python pillow psutil
    (Model file: download gemma-4-E2B-it-Q4_K_M.gguf from HuggingFace)
"""

import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path

import psutil

# ── Config ─────────────────────────────────────────────────────────────────────

MODEL_PATHS = {
    "e2b": Path("models/gemma-4-E2B-it-Q4_K_M.gguf"),
    "e4b": Path("models/gemma-4-E4B-it-Q4_K_M.gguf"),
}

# Gemma 4 recommended: high visual token budget for OCR tasks
VISION_TOKEN_BUDGET = 560   # use 1120 for higher accuracy, slower
MAX_TOKENS          = 1024  # enough for full JSON output
N_GPU_LAYERS        = -1    # -1 = use all available GPU layers
N_CTX               = 4096  # context window


# ── Latency thresholds ─────────────────────────────────────────────────────────

def interpret_latency(seconds: float) -> tuple[str, str]:
    """Returns (verdict, recommendation)"""
    if seconds < 10:
        return "✅ EXCELLENT", "Proceed with E2B. No UI changes needed."
    elif seconds < 15:
        return "✅ GOOD", "Proceed with E2B. Demo will feel responsive."
    elif seconds < 25:
        return "⚠️  ACCEPTABLE", "Add a progress bar with step labels. Document in benchmarks."
    elif seconds < 40:
        return "⚠️  SLOW", "Consider E2B with Q3_K_S quant (lower quality, faster). Add progress bar."
    else:
        return "❌ TOO SLOW", "Switch strategy: use E2B for OCR only, OpenCV for visual checks. Or use cloud with offline queue."


# ── Model loading ──────────────────────────────────────────────────────────────

def load_model(model_key: str = "e2b"):
    """Load Gemma 4 via llama-cpp-python with vision support."""
    from llama_cpp import Llama
    from llama_cpp.llama_chat_format import Gemma3ChatHandler

    model_path = MODEL_PATHS[model_key]
    if not model_path.exists():
        print(f"\n❌ Model not found at {model_path}")
        print(f"   Download from: https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF")
        print(f"   File: gemma-4-E2B-it-Q4_K_M.gguf")
        print(f"   Place in: {model_path.parent}/")
        sys.exit(1)

    print(f"Loading {model_key.upper()} from {model_path}...")
    t0 = time.perf_counter()

    chat_handler = Gemma3ChatHandler(clip_model_path="models/mmproj-gemma4.gguf")

    llm = Llama(
        model_path=str(model_path),
        chat_handler=chat_handler,
        n_ctx=N_CTX,
        n_gpu_layers=N_GPU_LAYERS,
        verbose=False,
    )

    load_time = time.perf_counter() - t0
    print(f"Model loaded in {load_time:.1f}s")
    return llm


# ── Single inference run ───────────────────────────────────────────────────────

def run_inference(llm, image_path: str, system_prompt: str) -> dict:
    """
    Run one complete inference pass. Returns timing and result data.
    """
    import base64

    from core.prompt import parse_model_output

    # Read and encode image
    with open(image_path, "rb") as f:
        image_bytes = f.read()
    b64 = base64.b64encode(image_bytes).decode("utf-8")

    messages = [
        {"role": "system", "content": system_prompt},
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{b64}"}
                },
                {
                    "type": "text",
                    "text": "Analyse this blister pack and return JSON."
                }
            ]
        }
    ]

    # Measure RAM before
    process = psutil.Process(os.getpid())
    ram_before = process.memory_info().rss / 1024 / 1024  # MB

    t0 = time.perf_counter()

    response = llm.create_chat_completion(
        messages=messages,
        max_tokens=MAX_TOKENS,
        temperature=0.1,   # low temperature for structured output
        response_format={"type": "json_object"},  # force JSON mode if supported
    )

    elapsed = time.perf_counter() - t0

    # Measure RAM after
    ram_after = process.memory_info().rss / 1024 / 1024
    ram_delta = ram_after - ram_before

    raw_output = response["choices"][0]["message"]["content"]
    tokens_generated = response["usage"]["completion_tokens"]
    tokens_per_sec = tokens_generated / elapsed if elapsed > 0 else 0

    parsed = parse_model_output(raw_output)
    parse_success = parsed is not None

    return {
        "latency_s":       round(elapsed, 2),
        "tokens_generated": tokens_generated,
        "tokens_per_sec":  round(tokens_per_sec, 1),
        "ram_delta_mb":    round(ram_delta, 1),
        "parse_success":   parse_success,
        "risk_score":      parsed.get("risk_score") if parsed else None,
        "risk_level":      parsed.get("risk_level") if parsed else None,
        "confidence":      parsed.get("confidence") if parsed else None,
        "raw_output_len":  len(raw_output),
    }


# ── Benchmark runner ───────────────────────────────────────────────────────────

def run_benchmark(image_path: str, model_key: str = "e2b", n_runs: int = 3):
    """
    Run N inference passes and report statistics.
    N=3 is enough to catch variance without wasting time.
    """
    from core.prompt import SYSTEM_PROMPT

    print(f"\n{'='*60}")
    print(f"PHAROS BENCHMARK — {model_key.upper()} — {n_runs} runs")
    print(f"Image: {image_path}")
    print(f"{'='*60}\n")

    llm = load_model(model_key)

    results = []
    for i in range(n_runs):
        print(f"Run {i+1}/{n_runs}...", end=" ", flush=True)
        result = run_inference(llm, image_path, SYSTEM_PROMPT)
        results.append(result)
        verdict, _ = interpret_latency(result["latency_s"])
        print(f"{result['latency_s']:.1f}s — {result['tokens_per_sec']} tok/s — parse: {'✅' if result['parse_success'] else '❌'}")

    # Statistics
    latencies = [r["latency_s"] for r in results]
    parse_successes = sum(1 for r in results if r["parse_success"])

    print(f"\n{'─'*60}")
    print(f"RESULTS:")
    print(f"  Median latency:      {statistics.median(latencies):.1f}s")
    print(f"  Min / Max:           {min(latencies):.1f}s / {max(latencies):.1f}s")
    if len(latencies) > 1:
        print(f"  Std deviation:       {statistics.stdev(latencies):.2f}s")
    print(f"  JSON parse success:  {parse_successes}/{n_runs}")
    print(f"  Avg RAM delta:       {statistics.mean([r['ram_delta_mb'] for r in results]):.0f} MB")
    print(f"  Avg tokens/sec:      {statistics.mean([r['tokens_per_sec'] for r in results]):.1f}")

    median_lat = statistics.median(latencies)
    verdict, recommendation = interpret_latency(median_lat)
    print(f"\n{'─'*60}")
    print(f"VERDICT: {verdict}")
    print(f"ACTION:  {recommendation}")
    print(f"{'─'*60}")

    # Save results
    output = {
        "model":      model_key,
        "image":      image_path,
        "n_runs":     n_runs,
        "results":    results,
        "summary": {
            "median_latency_s":   statistics.median(latencies),
            "min_latency_s":      min(latencies),
            "max_latency_s":      max(latencies),
            "parse_success_rate": parse_successes / n_runs,
            "verdict":            verdict,
            "recommendation":     recommendation,
        }
    }

    output_path = f"benchmark_results_{model_key}.json"
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nFull results saved to: {output_path}")
    print("Include this file in your repo — it's your technical proof.\n")

    return output


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Benchmark Gemma 4 vision inference for Pharos")
    parser.add_argument("--image",  required=True, help="Path to blister pack image")
    parser.add_argument("--model",  default="e2b", choices=["e2b", "e4b"], help="Model variant to benchmark")
    parser.add_argument("--runs",   type=int, default=3, help="Number of inference runs (default: 3)")
    args = parser.parse_args()

    if not Path(args.image).exists():
        print(f"❌ Image not found: {args.image}")
        sys.exit(1)

    run_benchmark(args.image, args.model, args.runs)
