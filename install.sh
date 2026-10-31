#!/usr/bin/env bash
# ccstatusline-extras installer: ccstatusline preset + cache-hit widget + statusLine wiring.
# Every touched file gets a timestamped backup; restore points are recorded in a state file.
set -euo pipefail

ASSUME_YES=false
NO_PRESET=false

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Install the ccstatusline-extras pack: preset + widgets for the Claude Code status line.

Options:
  --yes        Answer yes to every prompt (non-interactive)
  --no-preset  Do not write the ccstatusline preset config
  -h, --help   Show this help

Installed files:
  widget      ~/.local/bin/cc-cache-rate.py
  preset      ~/.config/ccstatusline/settings.json
  statusLine  ~/.claude/settings.json (command -> ccstatusline)
  state       ${XDG_DATA_HOME:-~/.local/share}/ccstatusline-extras/state.json
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --no-preset) NO_PRESET=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '[ccstatusline-extras] [info] %s\n' "$*"; }
ok()   { printf '[ccstatusline-extras] [ok] %s\n' "$*"; }
warn() { printf '[ccstatusline-extras] [warn] %s\n' "$*" >&2; }
die()  { printf '[ccstatusline-extras] [error] %s\n' "$*" >&2; exit 1; }

confirm() {
  local question="$1" default="${2:-y}" suffix="[Y/n]" ans=""
  if [ "$ASSUME_YES" = true ]; then
    return 0
  fi
  if [ "$default" = n ]; then
    suffix="[y/N]"
  fi
  printf '%s %s ' "$question" "$suffix"
  read -r ans || ans=""
  if [ -z "$ans" ]; then
    ans="$default"
  fi
  case "$ans" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

BACKUP_RESULT=""
backup_file() {
  local src="$1" ts dest n=0
  ts="$(date +%Y%m%d%H%M%S)"
  dest="${src}.bak.${ts}"
  while [ -e "$dest" ]; do
    n=$((n + 1))
    dest="${src}.bak.${ts}-${n}"
  done
  cp -- "$src" "$dest"
  BACKUP_RESULT="$dest"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

# ---------------------------------------------------------------- preflight
command -v python3 >/dev/null 2>&1 || die "python3 is required (the cache-hit widget and JSON merging need it)."

CCS_PREEXISTING=true
CCS_BY_US=false
if command -v ccstatusline >/dev/null 2>&1; then
  ok "found ccstatusline: $(command -v ccstatusline)"
else
  CCS_PREEXISTING=false
  if command -v npm >/dev/null 2>&1; then
    if confirm "ccstatusline not found. Install it now with 'npm install -g ccstatusline'?" y; then
      npm install -g ccstatusline || die "npm install failed; install ccstatusline manually and re-run."
      command -v ccstatusline >/dev/null 2>&1 || die "ccstatusline still not found; check that the npm global bin directory is on PATH."
      CCS_BY_US=true
    else
      die "ccstatusline is required. Install it manually: npm install -g ccstatusline"
    fi
  else
    die "ccstatusline (and npm) not found. Install Node.js 18+ first, then: npm install -g ccstatusline"
  fi
fi

SETTINGS_PATH="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_PATH" ]; then
  if ! python3 - "$SETTINGS_PATH" >/dev/null 2>&1 <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict):
    raise SystemExit(1)
PY
  then
    die "existing $SETTINGS_PATH is not a valid JSON object; fix it first (no changes made)."
  fi
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "$HOME/.local/bin is not in PATH (the widget uses an absolute path, so the status line still works)." ;;
esac

# ------------------------------------------------------------- 1. widget
SCRIPT_PATH="$HOME/.local/bin/cc-cache-rate.py"
SCRIPT_BACKUP=""
[ -f "$SCRIPT_DIR/bin/cc-cache-rate.py" ] || die "repo file missing: $SCRIPT_DIR/bin/cc-cache-rate.py"
mkdir -p "$HOME/.local/bin"
if [ -f "$SCRIPT_PATH" ] && ! cmp -s "$SCRIPT_DIR/bin/cc-cache-rate.py" "$SCRIPT_PATH"; then
  backup_file "$SCRIPT_PATH"
  SCRIPT_BACKUP="$BACKUP_RESULT"
fi
cp -- "$SCRIPT_DIR/bin/cc-cache-rate.py" "$SCRIPT_PATH.tmp-cse"
mv -- "$SCRIPT_PATH.tmp-cse" "$SCRIPT_PATH"
chmod 755 "$SCRIPT_PATH"
ok "installed widget: $SCRIPT_PATH"

# ------------------------------------------------------- 2. ccstatusline preset
CONFIG_PATH="$HOME/.config/ccstatusline/settings.json"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ccstatusline-extras"
STATE_FILE="$STATE_DIR/state.json"
CONFIG_BACKUP=""
CONFIG_WRITTEN=false
CONFIG_SNAPSHOT=""

if [ "$NO_PRESET" = false ]; then
  PRESET_SRC="$SCRIPT_DIR/preset/settings.json"
  [ -f "$PRESET_SRC" ] || die "repo file missing: $PRESET_SRC"
  PRESET_CONTENT="$(cat "$PRESET_SRC")"
  GENERATED="${PRESET_CONTENT//__CC_CACHE_RATE__/$SCRIPT_PATH}"
  printf '%s\n' "$GENERATED" > "$TMP_DIR/preset.generated.json"

  if [ -f "$CONFIG_PATH" ] && cmp -s "$TMP_DIR/preset.generated.json" "$CONFIG_PATH"; then
    info "ccstatusline config already matches the preset; left untouched."
  else
    mkdir -p "$(dirname "$CONFIG_PATH")"
    if [ -f "$CONFIG_PATH" ]; then
      backup_file "$CONFIG_PATH"
      CONFIG_BACKUP="$BACKUP_RESULT"
    fi
    cp -- "$TMP_DIR/preset.generated.json" "$CONFIG_PATH.tmp-cse"
    mv -- "$CONFIG_PATH.tmp-cse" "$CONFIG_PATH"
    mkdir -p "$STATE_DIR"
    cp -- "$TMP_DIR/preset.generated.json" "$STATE_DIR/installed-config.json.tmp-cse"
    mv -- "$STATE_DIR/installed-config.json.tmp-cse" "$STATE_DIR/installed-config.json"
    CONFIG_WRITTEN=true
    CONFIG_SNAPSHOT="$STATE_DIR/installed-config.json"
    ok "installed ccstatusline preset: $CONFIG_PATH"
  fi
else
  info "skipping ccstatusline preset (--no-preset)."
fi

# --------------------------------------------------- 3. statusLine wiring
SETTINGS_BACKUP=""
SETTINGS_EXISTED=false
if [ -f "$SETTINGS_PATH" ]; then
  SETTINGS_EXISTED=true
  backup_file "$SETTINGS_PATH"
  SETTINGS_BACKUP="$BACKUP_RESULT"
else
  mkdir -p "$HOME/.claude"
fi

python3 - "$SETTINGS_PATH" "$TMP_DIR/sl-result.txt" <<'PY'
import json, os, sys

path, out = sys.argv[1], sys.argv[2]
desired = {"type": "command", "command": "ccstatusline", "refreshInterval": 10}

existed = os.path.exists(path)
if existed:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise SystemExit("settings file is not a JSON object")
else:
    data = {}

prev_present = isinstance(data.get("statusLine"), dict)
prev = data.get("statusLine") if prev_present else None

if existed and data.get("statusLine") == desired:
    action = "unchanged"
else:
    action = "changed" if existed else "created"
    data["statusLine"] = desired
    tmp = path + ".tmp-cse"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)

with open(out, "w", encoding="utf-8") as f:
    f.write(action + "\n")
    f.write(("true" if prev_present else "false") + "\n")
    if prev is not None:
        f.write(json.dumps(prev, ensure_ascii=False) + "\n")
    else:
        f.write("null\n")
PY

SL_ACTION=""
PREV_PRESENT="false"
PREV_JSON="null"
if [ -f "$TMP_DIR/sl-result.txt" ]; then
  {
    IFS= read -r SL_ACTION || true
    IFS= read -r PREV_PRESENT || true
    IFS= read -r PREV_JSON || true
  } < "$TMP_DIR/sl-result.txt"
  [ -n "$SL_ACTION" ] || SL_ACTION="unknown"
  [ -n "$PREV_PRESENT" ] || PREV_PRESENT="false"
  [ -n "$PREV_JSON" ] || PREV_JSON="null"
fi

case "$SL_ACTION" in
  unchanged) info "statusLine already configured; $SETTINGS_PATH left untouched." ;;
  changed)   ok "updated statusLine in $SETTINGS_PATH" ;;
  created)   ok "created $SETTINGS_PATH with statusLine config" ;;
  *)         die "unexpected result while configuring statusLine: '$SL_ACTION'" ;;
esac

# ------------------------------------------------------------- 4. state file
INSTALLED_AT="$(date +%Y-%m-%dT%H:%M:%S%z)"
python3 - "$STATE_FILE" "$INSTALLED_AT" "$CCS_PREEXISTING" "$CCS_BY_US" \
  "$SCRIPT_PATH" "$SCRIPT_BACKUP" \
  "$CONFIG_PATH" "$CONFIG_BACKUP" "$CONFIG_WRITTEN" "$CONFIG_SNAPSHOT" \
  "$SETTINGS_PATH" "$SETTINGS_BACKUP" "$SETTINGS_EXISTED" \
  "$PREV_PRESENT" "$PREV_JSON" <<'PY'
import json, os, sys

state_file = sys.argv[1]
(a_installed_at, a_ccs_pre, a_ccs_byus,
 a_script, a_script_bak,
 a_conf, a_conf_bak, a_conf_written, a_conf_snap,
 a_set, a_set_bak, a_set_existed,
 a_prev_present, a_prev_json) = sys.argv[2:16]

def or_none(v):
    return v if v not in ("", None) else None

def as_bool(v):
    return v == "true"

new = {
    "version": 1,
    "installed_at": a_installed_at,
    "installed_at_first": a_installed_at,
    "ccstatusline_preexisting": as_bool(a_ccs_pre),
    "ccstatusline_installed_by_us": as_bool(a_ccs_byus),
    "script_path": or_none(a_script),
    "script_backup": or_none(a_script_bak),
    "config_path": or_none(a_conf),
    "config_backup": or_none(a_conf_bak),
    "config_written": as_bool(a_conf_written),
    "config_snapshot": or_none(a_conf_snap),
    "settings_path": or_none(a_set),
    "settings_backup": or_none(a_set_bak),
    "settings_existed_before": as_bool(a_set_existed),
    "previous_statusline_present": as_bool(a_prev_present),
    "previous_statusline": json.loads(a_prev_json) if a_prev_json not in ("", "null") else None,
}
old = None
if os.path.exists(state_file):
    try:
        with open(state_file, encoding="utf-8") as f:
            old = json.load(f)
    except (OSError, ValueError):
        old = None

if isinstance(old, dict):
    merged = dict(new)
    merged["installed_at_first"] = old.get("installed_at_first") or old.get("installed_at") or new["installed_at_first"]
    for key in ("script_backup", "config_backup", "settings_backup", "config_snapshot"):
        if old.get(key):
            merged[key] = old[key]
    for key in ("ccstatusline_preexisting", "settings_existed_before"):
        if key in old:
            merged[key] = old[key]
    if old.get("ccstatusline_installed_by_us"):
        merged["ccstatusline_installed_by_us"] = True
    if old.get("config_written"):
        merged["config_written"] = True
    if "previous_statusline_present" in old:
        merged["previous_statusline_present"] = old["previous_statusline_present"]
        merged["previous_statusline"] = old.get("previous_statusline")
    new = merged

os.makedirs(os.path.dirname(state_file), exist_ok=True)
tmp = state_file + ".tmp-cse"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(new, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, state_file)
PY

ok "ccstatusline-extras installed."
info "  widget  : $SCRIPT_PATH"
if [ "$CONFIG_WRITTEN" = true ]; then
  info "  preset  : $CONFIG_PATH"
fi
info "  status  : $SETTINGS_PATH"
if [ -n "$SCRIPT_BACKUP" ]; then info "  backup  : $SCRIPT_BACKUP"; fi
if [ -n "$CONFIG_BACKUP" ]; then info "  backup  : $CONFIG_BACKUP"; fi
if [ -n "$SETTINGS_BACKUP" ]; then info "  backup  : $SETTINGS_BACKUP"; fi
info "Restart Claude Code (or wait up to 10s) to see the new status line."
info "Uninstall: bash \"$SCRIPT_DIR/uninstall.sh\""
