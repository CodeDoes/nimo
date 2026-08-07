#!/usr/bin/env bash
# nimo L1 CLI integration tests (offline, deterministic, no GPU/model).
#
# Spawns the harness binary (one binary for real+stub), driven by a
# scripted model (--script-replies <json array>). Asserts black-box behavior:
# exit codes, stdout, session JSONL, written files, workspace, resume.
#
# This is the "parts work together" layer: real arg parsing -> bootstrap ->
# one-shot/interactive loop -> session save -> file write -> exit.
#
# Usage: devenv shell scripts/cli_test.sh
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
HARNESS="$ROOT/build/harness_offline"
FIXTURES="$ROOT/tests/fixtures"
WORK="$(mktemp -d /tmp/nimo-l1-XXXXXX)"
PASS=0; FAIL=0

trap 'rm -rf "$WORK"' EXIT

echo "nima L1 CLI integration tests  $(date -Iseconds)"
echo "harness=$HARNESS  work=$WORK"
echo "----------------------------------------------"

# --- helpers ---------------------------------------------------------------
check() {  # name cond detail   (cond is a shell expr; non-zero/false => fail)
  local name="$1" expr="$2"
  if eval "$expr"; then
    PASS=$((PASS+1)); printf "  [PASS] %s\n" "$name"
  else
    FAIL=$((FAIL+1)); printf "  [FAIL] %s\n      %s\n" "$name" "${3:-}"
  fi
}
run_harness() {  # args... -> stdout in OUT, exit code in RC
  OUT="$("$HARNESS" "$@" 2>&1)"; RC=$?
}

# 1. one-shot: exit 0, streams scripted reply, saves session file ------------
cd "$WORK"
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            -s one.jsonl -p "write a haiku about AI"
check "one-shot exits 0"                "[[ $RC -eq 0 ]]"
check "one-shot streams reply to stdout" "[[ \"$OUT\" == *'A mind in code.'* ]]" "$OUT"
check "one-shot saves session file"     "[[ -f one.jsonl ]]"
check "session has user + text + plan"  "[[ $(grep -c '\"role\":\"user\"' one.jsonl) -ge 1 && $(grep -c 'A mind in code' one.jsonl) -ge 1 ]]"
check "session header is pi v3"         "head -1 one.jsonl | grep -q '\"version\":3'" "$(head -1 one.jsonl)"

# 2. deterministic file write: "write a file called X" ------------------------
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            -w . -s two.jsonl -p "write a file called NOTES.md with a haiku"
check "file-write exits 0"              "[[ $RC -eq 0 ]]"
check "file-write reports [file] wrote" "[[ \"$OUT\" == *'[file] wrote'* ]]" "$OUT"
check "NOTES.md created with content"   "[[ -s NOTES.md ]]"
check "NOTES.md contains scripted text" "[[ \"$(cat NOTES.md 2>/dev/null)\" == *'A mind in code'* ]]"

# 3. workspace isolation: -w creates dir, file lands there --------------------
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            -w "$WORK/ws3" -s ws3/sess.jsonl -p "write a file called out.md with a haiku"
check "workspace dir created"           "[[ -d \"$WORK/ws3\" ]]"
check "workspace-relative file written" "[[ -s \"$WORK/ws3/out.md\" ]]"
check "no stray file in cwd"            "[[ ! -e out.md ]]"

# 4. session resume: second run says resumed and grows the file ----------------
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            -s resume.jsonl -p "first turn"
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            -s resume.jsonl -p "second turn"
check "second run reports resumed"      "[[ \"$OUT\" == *'resumed session'* ]]" "$OUT"
check "session file grew (>=5 messages)" "[[ $(wc -l < resume.jsonl) -ge 5 ]]" "$(wc -l < resume.jsonl) lines"

# 5. smoke flag path with scripted replies -------------------------------------
run_harness --script-replies "$FIXTURES/haiku_replies.json" \
            --smoke --prompt "Say OK." --max-tokens 4
check "smoke prints [smoke] reply"      "[[ \"$OUT\" == *'[smoke] reply'* ]]" "$OUT"
check "smoke reply equals scripted"     "[[ \"$OUT\" == *'A mind in code'* ]]" "$OUT"

# 6. error paths ---------------------------------------------------------------
run_harness --script-replies "$FIXTURES/haiku_replies.json" -p "x" --bogus-flag
check "unknown flag exits nonzero"      "[[ $RC -ne 0 ]]" "rc=$RC"
check "unknown flag named in message"   "[[ \"$OUT\" == *'--bogus-flag'* ]]" "$OUT"

run_harness --script-replies /nonexistent.json -p "x"
check "missing script-replies is nonfatal" \
          "[[ \"$OUT\" == *'no model'* || \"$OUT\" == *'scripted model'* ]]" "$OUT"

echo "----------------------------------------------"
echo "  $PASS passed, $FAIL failed"
echo "  exit=$([[ $FAIL -eq 0 ]]; echo $?)"
[[ $FAIL -eq 0 ]]