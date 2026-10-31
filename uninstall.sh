#!/usr/bin/env bash
# ccstatusline-extras uninstaller: restores what install.sh changed, based on the state file.
# Keeps backups on disk; does not remove ccstatusline itself.
set -euo pipefail

ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: bash uninstall.sh [options]

Undo a ccstatusline-extras installation:
  - restore the previous ccstatusline config (or remove the installed preset)
  - restore or remove ~/.local/bin/cc-cache-rate.py
  - restore the previous statusLine in ~/.claude/settings.json

Options:
  --yes        Answer yes to every prompt (non-interactive)
  -h, --help   Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

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

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ccstatusline-extras"
STATE_FILE="$STATE_DIR/state.json"
[ -f "$STATE_FILE" ] || die "nothing to uninstall (state file not found: $STATE_FILE)."

if ! python3 - "$STATE_FILE" >/dev/null 2>&1 <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict):
    raise SystemExit(1)
PY
then
  die "state file is corrupt: $STATE_FILE"
fi

read_state() {
  python3 - "$STATE_FILE" "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    state = json.load(f)
v = state.get(sys.argv[2])
if v is None:
    print("")
elif isinstance(v, bool):
    print("true" if v else "false")
elif isinstance(v, (dict, list)):
    print(json.dumps(v, ensure_ascii=False))
else:
    print(v)
PY
}

CONFIG_WRITTEN="$(read_state config_written)"
CONFIG_PATH="$(read_state config_path)"
CONFIG_BACKUP="$(read_state config_backup)"
CONFIG_SNAPSHOT="$(read_state config_snapshot)"
SETTINGS_PATH="$(read_state settings_path)"
SETTINGS_BACKUP="$(read_state settings_backup)"
PREV_PRESENT="$(read_state previous_statusline_present)"
PREV_JSON="$(read_state previous_statusline)"
SCRIPT_PATH="$(read_state script_path)"
SCRIPT_BACKUP="$(read_state script_backup)"
CCS_BY_US="$(read_state ccstatusline_installed_by_us)"

# ---------- ccstatusline config ----------
if [ "$CONFIG_WRITTEN" = true ] && [ -n "$CONFIG_PATH" ]; then
  if [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then
    if confirm "Restore original ccstatusline config from $CONFIG_BACKUP? (current config will be replaced)" y; then
      cp -- "$CONFIG_BACKUP" "$CONFIG_PATH"
      ok "restored ccstatusline config from backup"
    else
      info "kept current ccstatusline config"
    fi
  elif [ -n "$CONFIG_SNAPSHOT" ] && [ -f "$CONFIG_SNAPSHOT" ]; then
    if [ ! -f "$CONFIG_PATH" ]; then
      info "ccstatusline config already gone"
    elif cmp -s "$CONFIG_PATH" "$CONFIG_SNAPSHOT"; then
      if confirm "Remove preset ccstatusline config ($CONFIG_PATH)?" y; then
        rm -f -- "$CONFIG_PATH"
        ok "removed preset ccstatusline config"
      else
        info "kept ccstatusline config"
      fi
    else
      warn "ccstatusline config was modified since install; keeping it"
    fi
  else
    warn "no backup or snapshot for ccstatusline config; leaving it as is"
  fi
else
  info "ccstatusline config was not written by install; nothing to undo"
fi

# ---------- statusLine ----------
if [ -n "$SETTINGS_PATH" ] && [ -f "$SETTINGS_PATH" ]; then
  if SL_OUT="$(python3 - "$SETTINGS_PATH" "$PREV_PRESENT" "$PREV_JSON" <<'PY'
import json, os, sys

path, present_s, prev_json_s = sys.argv[1], sys.argv[2], sys.argv[3]
desired = {"type": "command", "command": "ccstatusline", "refreshInterval": 10}

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except ValueError:
    print("invalid")
    sys.exit(0)
if not isinstance(data, dict):
    print("invalid")
    sys.exit(0)

if present_s == "true" and prev_json_s:
    prev = json.loads(prev_json_s)
    cur = data.get("statusLine")
    if cur == prev:
        print("noop")
        sys.exit(0)
    if cur != desired:
        print("modified")
        sys.exit(0)
    data["statusLine"] = prev
else:
    if "statusLine" not in data:
        print("noop")
        sys.exit(0)
    cur = data.get("statusLine")
    if cur is not None and cur != desired:
        print("modified")
        sys.exit(0)
    del data["statusLine"]

tmp = path + ".tmp-cse"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print("restored")
PY
  )"; then
    case "$SL_OUT" in
      restored) ok "restored previous statusLine in $SETTINGS_PATH" ;;
      noop)     info "statusLine already matches the previous value" ;;
      modified) warn "statusLine was changed since install; leaving it as is" ;;
      invalid)  warn "$SETTINGS_PATH is not valid JSON; fix it manually" ;;
      *)        warn "could not update $SETTINGS_PATH" ;;
    esac
  else
    warn "could not update $SETTINGS_PATH (unexpected error)"
  fi
elif [ -n "$SETTINGS_PATH" ]; then
  warn "settings file not found: $SETTINGS_PATH (skipping statusLine restore)"
fi

# ---------- widget ----------
if [ -n "$SCRIPT_PATH" ]; then
  if [ -n "$SCRIPT_BACKUP" ] && [ -f "$SCRIPT_BACKUP" ]; then
    if confirm "Restore previous cc-cache-rate.py from $SCRIPT_BACKUP?" y; then
      mkdir -p "$(dirname "$SCRIPT_PATH")"
      cp -- "$SCRIPT_BACKUP" "$SCRIPT_PATH"
      ok "restored widget script from backup"
    else
      info "kept current widget script"
    fi
  elif [ -f "$SCRIPT_PATH" ]; then
    if confirm "Remove installed widget script ($SCRIPT_PATH)?" y; then
      rm -f -- "$SCRIPT_PATH"
      ok "removed widget script"
    else
      info "kept widget script"
    fi
  else
    info "widget script already gone"
  fi
fi

# ---------- state ----------
case "$STATE_DIR" in
  */ccstatusline-extras) rm -rf -- "$STATE_DIR" ;;
  *) die "refusing to remove unexpected state directory: $STATE_DIR" ;;
esac

ok "ccstatusline-extras uninstalled."
if [ -n "$SCRIPT_BACKUP" ] && [ -f "$SCRIPT_BACKUP" ]; then info "kept backup: $SCRIPT_BACKUP"; fi
if [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then info "kept backup: $CONFIG_BACKUP"; fi
if [ -n "$SETTINGS_BACKUP" ] && [ -f "$SETTINGS_BACKUP" ]; then info "kept backup: $SETTINGS_BACKUP"; fi
info "ccstatusline itself was not removed."
if [ "$CCS_BY_US" = true ]; then
  info "It was installed by install.sh; remove it with: npm uninstall -g ccstatusline"
fi
info "Restart Claude Code to refresh the status line."
