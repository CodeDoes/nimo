#!/usr/bin/env bash
# nimo backend smoke test: CPU, NVIDIA (CUDA), AMD (Vulkan).
# Selects each backend through the SINGLE controlled path: rwkv.selectBackend(cfg)
# fed by NIMO_BACKEND (config > env > rwkv default > backend modules; RFC 7500).
# Uses the harness single-shot NIMO_SMOKE mode (no agent loop, no system prompt):
# load model once, generate a short reply, report PASS/FAIL + wall time.
# No pipes: harness output goes to a temp file, checked with bash patterns.
#
# Usage:   devenv shell scripts/smoke_test.sh
set -u
cd "$(dirname "$0")/.."
OUT=/tmp/nimo_smoke_out.txt
SMOKE_PROMPT="${SMOKE_PROMPT:-Say OK.}"
SMOKE_TOKENS="${SMOKE_TOKENS:-16}"
HARNESS="${HARNESS:-./build/harness}"

echo "nimo backend smoke test  $(date -Iseconds)"
echo "prompt=\"$SMOKE_PROMPT\"  tokencap=$SMOKE_TOKENS  harness=$HARNESS"
echo "----------------------------------------------"

run_backend() {  # name backend_kind libdirs
  local name="$1" kind="$2" libdir="$3"
  local libs="$libdir:${LD_LIBRARY_PATH:-}"   # keep host resolver paths (system NVIDIA/VK loader)
  local start end secs rc
  start=$(date +%s)
  env LD_LIBRARY_PATH="$libs" \
    NIMO_BACKEND="$kind" NIMO_SMOKE=1 NIMO_SMOKE_PROMPT="$SMOKE_PROMPT" NIMO_MAX_TOKENS="$SMOKE_TOKENS" \
    "$HARNESS" < /dev/null > "$OUT" 2>&1
  rc=$?
  end=$(date +%s); secs=$((end - start))
  if [[ $rc -eq 0 && -f "$OUT" && $(<"$OUT") == *"[smoke] reply"* ]]; then
    printf "  %-8s PASS  %ss\n" "$name" "$secs"
  else
    printf "  %-8s FAIL  %ss\n" "$name" "$secs"
    [[ -f "$OUT" ]] && printf "      tail: %s\n" "$(tail -n 3 "$OUT")"
  fi
}

have_nvidia=0; have_amd_vulkan=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 && have_nvidia=1
command -v vulkaninfo >/dev/null 2>&1 && [[ "$(vulkaninfo --summary 2>&1)" == *AMD* ]] && have_amd_vulkan=1
echo "detected backends: nvidia=$have_nvidia amd/vulkan=$have_amd_vulkan"
echo "----------------------------------------------"

echo "== CPU =="
run_backend cpu    cpu    "rwkv.cpp:rwkv.cpp/ggml/src:rwkv.cpp/ggml/src/ggml-cuda"

echo "== NVIDIA (CUDA) =="
if [[ $have_nvidia -eq 1 ]]; then
  run_backend nvidia cuda  "rwkv.cpp:rwkv.cpp/ggml/src:rwkv.cpp/ggml/src/ggml-cuda:/usr/lib/x86_64-linux-gnu"
else
  printf "  %-8s SKIP  %s\n" nvidia "nvidia-smi unavailable"
fi

echo "== AMD (Vulkan) =="
VK_LIB="${NIMO_AMD_LIB:-rwkv.cpp/build-amd/librwkv.so}"
if [[ -f "$VK_LIB" && $have_amd_vulkan -eq 1 ]]; then
  run_backend amd "vulkan" "$(cd "$(dirname "$VK_LIB")" && pwd):rwkv.cpp:rwkv.cpp/ggml/src:/usr/lib/x86_64-linux-gnu"
else
  printf "  %-8s SKIP  %s\n" amd "Vulkan backend not built (scripts/build/amd-vulkan.sh)"
fi

echo "----------------------------------------------"
echo "done."