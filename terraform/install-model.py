from huggingface_hub import snapshot_download

# This will download the weights, config, and tokenizer files
print("Starting download...")
snapshot_download(
    repo_id="TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    local_dir="./tinyllama-model",
    local_dir_use_symlinks=False
)
print("Download complete! Check the ./tinyllama-model folder.")