#!/usr/bin/env bash
# nimo backend smoke test: NVIDIA (CUDA) or CPU fallback.
# Selects each backend through the SINGLE controlled path: rwkv.selectBackend(cfg)
# fed by an explicit --backend flag (same convention as generate.nim) — no env
# precedence chain.
# Uses the harness single-shot --smoke mode (no agent loop, no system prompt):
# load model once, generate a short reply, report PASS/FAIL + wall time.
# No pipes: harness output goes to a temp file, checked with bash patterns.
#
# Priority: CUDA if available, otherwise CPU.
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

run_backend() {  # name backend_kind
  local name="$1" kind="$2"
  local start end secs rc
  start=$(date +%s)
  "$HARNESS" --backend "$kind" --smoke --prompt "$SMOKE_PROMPT" --max-tokens "$SMOKE_TOKENS" \
    < /dev/null > "$OUT" 2>&1
  rc=$?
  end=$(date +%s); secs=$((end - start))
  if [[ $rc -eq 0 && -f "$OUT" && $(<"$OUT") == *"[smoke] reply"* ]]; then
    printf "  %-8s PASS  %ss\n" "$name" "$secs"
    exit 0  # success, stop here
  else
    printf "  %-8s FAIL  %ss\n" "$name" "$secs"
    [[ -f "$OUT" ]] && printf "      tail: %s\n" "$(tail -n 3 "$OUT")"
  fi
}

have_nvidia=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 && have_nvidia=1
echo "detected backends: nvidia=$have_nvidia"
echo "----------------------------------------------"

if [[ $have_nvidia -eq 1 ]]; then
  echo "== NVIDIA (CUDA) =="
  run_backend nvidia cuda
else
  echo "== CPU (fallback) =="
  run_backend cpu cpu
fi

echo "----------------------------------------------"
echo "done."
