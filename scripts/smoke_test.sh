#!/usr/bin/env bash
# nimo backend smoke test: CPU, NVIDIA (CUDA), AMD (Vulkan/CLBlast).
# Uses the harness's single-shot NIMO_SMOKE mode (no agent loop, no system
# prompt): load model once, generate a short reply, report PASS/FAIL + wall time.
# No pipes: harness output goes to a temp file, then checked with bash patterns.
#
# Usage:   devenv shell scripts/smoke_test.sh
set -u
cd "$(dirname "$0")/.."
OUT=/tmp/nimo_smoke_out.txt
SMOKE_PROMPT="${SMOKE_PROMPT:-Say OK.}"
SMOKE_TOKENS="${SMOKE_TOKENS:-16}"
base_lib="rwkv.cpp:rwkv.cpp/ggml/src:rwkv.cpp/ggml/src/ggml-cuda"

echo "nimo backend smoke test  $(date -Iseconds)"
echo "prompt=\"$SMOKE_PROMPT\"  tokencap=$SMOKE_TOKENS"
echo "----------------------------------------------"

run_backend() {  # name libdir extra_envs
  local name="$1" libdir="$2" extra="$3"
  local libs="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"   # keep system driver path
  local start end secs rc
  start=$(date +%s)
  env LD_LIBRARY_PATH="$libs" $extra \
    NIMO_SMOKE=1 NIMO_SMOKE_PROMPT="$SMOKE_PROMPT" NIMO_MAX_TOKENS="$SMOKE_TOKENS" \
    ./build/harness < /dev/null > "$OUT" 2>&1
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
echo "detected backends: cpu=1 nvidia=$have_nvidia amd/vulkan=$have_amd_vulkan"
echo "----------------------------------------------"

echo "== CPU =="
run_backend cpu "$base_lib" "NIMO_GPU_LAYERS=0 NIMO_ALLOW_CPU_FALLBACK=1"

echo "== NVIDIA (CUDA) =="
if [[ $have_nvidia -eq 1 ]]; then
  run_backend nvidia "$base_lib" ""
else
  printf "  %-8s FAIL  %s\n" nvidia "nvidia-smi unavailable"
fi

echo "== AMD (Vulkan / CLBlast) =="
AMD_LIB="${NIMO_AMD_LIB:-rwkv.cpp/build-amd/librwkv.so}"
if [[ -f "$AMD_LIB" && $have_amd_vulkan -eq 1 ]]; then
  run_backend amd "$(cd "$(dirname "$AMD_LIB")" && pwd):rwkv.cpp:rwkv.cpp/ggml/src" ""
else
  printf "  %-8s SKIP  %s\n" amd "AMD Vulkan backend not built: scripts/build/amd-vulkan.sh"
fi

echo "----------------------------------------------"
echo "done."