#!/usr/bin/env bash
# Smoke test: exercises install.sh / uninstall.sh against a throwaway HOME.
# Never touches the real home directory. Usage: bash test/smoke.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
FAIL=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }
cleanup() { rm -rf -- "$SB"; }
trap cleanup EXIT

mkdir -p "$SB/.local/bin"

# Synthetic transcript for render checks: one usage entry before and one after a
# compaction boundary.  In: must show the whole-session total (1.2M + 0.8M),
# proving the counter never resets at compactions, and ↻ must be 1.
cat > "$SB/transcript.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-01-01T10:00:00.000Z","message":{"stop_reason":"end_turn","usage":{"input_tokens":1200000,"output_tokens":30,"cache_creation_input_tokens":50,"cache_read_input_tokens":500}}}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-01-01T10:05:00.000Z","compactMetadata":{"preTokens":500000,"postTokens":120000}}
{"type":"assistant","timestamp":"2026-01-01T10:10:00.000Z","message":{"stop_reason":"end_turn","usage":{"input_tokens":800000,"output_tokens":40,"cache_creation_input_tokens":60,"cache_read_input_tokens":600}}}
EOF

echo "== install (fresh home) =="
HOME="$SB" bash "$REPO/install.sh" --yes >"$SB/install.out" 2>&1 || { cat "$SB/install.out"; echo "install.sh failed"; exit 1; }

[ -x "$SB/.local/bin/cc-cache-rate.py" ] && pass "widget installed" || fail "widget missing"
[ -f "$SB/.config/ccstatusline/settings.json" ] && pass "preset written" || fail "preset missing"
if grep -q "__CC_CACHE_RATE__" "$SB/.config/ccstatusline/settings.json"; then fail "placeholder left"; else pass "placeholder replaced"; fi
python3 - "$SB" <<'PY' && pass "statusLine wired" || fail "statusLine wrong"
import json, sys
sb = sys.argv[1]
d = json.load(open(sb + "/.claude/settings.json", encoding="utf-8"))
assert d["statusLine"] == {"type": "command", "command": "ccstatusline", "refreshInterval": 10}, d
PY
[ -f "$SB/.local/share/ccstatusline-extras/state.json" ] && pass "state written" || fail "state missing"

if command -v ccstatusline >/dev/null 2>&1; then
  BODY='{"session_id":"smoke","cwd":"/tmp","workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"model":{"id":"x","display_name":"Test"},"version":"0","output_style":{"name":"default"},"transcript_path":"'"$SB"'/transcript.jsonl","context_window":{"context_window_size":200000,"used_percentage":10,"remaining_percentage":90,"total_input_tokens":1000,"total_output_tokens":20,"current_usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":800}},"prompt_cache":{"hit_ratio":0.8},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_lines_added":0,"total_lines_removed":0}}'
  if OUT="$(printf '%s' "$BODY" | HOME="$SB" CCSTATUSLINE_WIDTH=120 ccstatusline 2>/dev/null)"; then
    # ccstatusline renders ASCII spaces as U+00A0 (NBSP); normalize before matching.
    CLEAN="$(printf '%s' "$OUT" | python3 -c 'import re, sys; t = re.sub(r"\x1b\[[0-9;]*m", "", sys.stdin.read()); print(t.replace("\u00a0", " "), end="")')"
    case "$CLEAN" in
      *"Cache Hit: 80.0%"*) pass "render shows cache hit" ;;
      *) fail "render lacks cache hit: $CLEAN" ;;
    esac
    case "$CLEAN" in
      *"In: 2.0M"*) pass "render In: spans compactions" ;;
      *) fail "render lacks In: 2.0M: $CLEAN" ;;
    esac
    case "$CLEAN" in
      *"↻ 1"*) pass "render shows compaction count" ;;
      *) fail "render lacks ↻ 1: $CLEAN" ;;
    esac
  else
    fail "ccstatusline render exited non-zero"
  fi
else
  echo "SKIP: ccstatusline not on PATH; render check skipped"
fi

echo "== reinstall (idempotent) =="
HOME="$SB" bash "$REPO/install.sh" --yes >"$SB/install2.out" 2>&1 || { cat "$SB/install2.out"; echo "reinstall failed"; exit 1; }
grep -q "already matches the preset" "$SB/install2.out" && pass "reinstall skipped preset" || fail "reinstall rewrote preset"
grep -q "statusLine already configured" "$SB/install2.out" && pass "reinstall skipped statusLine" || fail "reinstall rewrote statusLine"

echo "== uninstall =="
HOME="$SB" bash "$REPO/uninstall.sh" --yes >"$SB/uninstall.out" 2>&1 || { cat "$SB/uninstall.out"; echo "uninstall failed"; exit 1; }
[ ! -e "$SB/.config/ccstatusline/settings.json" ] && pass "preset removed (no backup case)" || fail "preset still present"
python3 - "$SB" <<'PY' && pass "statusLine removed" || fail "statusLine remains"
import json, sys, os
sb = sys.argv[1]
p = sb + "/.claude/settings.json"
assert os.path.exists(p)
d = json.load(open(p, encoding="utf-8"))
assert "statusLine" not in d, d
PY
[ ! -e "$SB/.local/bin/cc-cache-rate.py" ] && pass "widget removed" || fail "widget remains"
[ ! -e "$SB/.local/share/ccstatusline-extras" ] && pass "state removed" || fail "state remains"

if [ "$FAIL" = 0 ]; then
  echo "== RESULT: OK =="
else
  echo "== RESULT: FAILED =="
fi
exit "$FAIL"
