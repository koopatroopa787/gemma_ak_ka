import os

from huggingface_hub import login
from unsloth import FastVisionModel

# Step 1: Login to HuggingFace
# Replace "hf_your_token_here" with your actual HuggingFace token
# Or set it as an environment variable and use login(token=os.environ.get("HF_TOKEN"))
login(token=os.environ.get("HF_TOKEN"))  # set HF_TOKEN env var before running

# Step 2: Download base model
print("Downloading base model...")
model, tokenizer = FastVisionModel.from_pretrained(
    model_name="unsloth/gemma-4-e2b-it",
    load_in_4bit=True,
    max_seq_length=2048,
)

# Step 3: Load your LoRA adapters
print("Loading LoRA adapters...")
model.load_adapter("./pharos_gemma4_final/model")

# Step 4: Save the merged model locally
print("Saving merged model...")
model.save_pretrained_merged(
    "E:/Models/gemma4_e2b_pharos",
    tokenizer,
    save_method="merged_4bit",
)
print("Saved merged model locally to E:/Models/gemma4_e2b_pharos")
