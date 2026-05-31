# Place your GGUF model files here.
#
# Example download with llama.cpp's download utility:
#   docker run --rm -v $(pwd)/models:/models ghcr.io/ggml-org/llama.cpp:server-cuda \
#     --hf-repo NousResearch/Hermes-3-Llama-3.1-8B-GGUF \
#     --hf-file Hermes-3-Llama-3.1-8B.Q4_K_M.gguf \
#     -o /models/hermes-3-llama-3.1-8b.q4_k_m.gguf
#
# Then set in .env:
#   LLAMA_MODEL=hermes-3-llama-3.1-8b.q4_k_m.gguf
#
# Popular Hermes models on HuggingFace:
#   NousResearch/Hermes-3-Llama-3.1-8B-GGUF
#   NousResearch/Hermes-3-Llama-3.1-70B-GGUF
#   NousResearch/Hermes-2-Pro-Llama-3-8B-GGUF
