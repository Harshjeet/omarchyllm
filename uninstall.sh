#!/usr/bin/env bash

# ==============================================================================
# Omarchy LLM Uninstaller
# Uninstalls and cleanly removes Omarchy LLM from any Omarchy Hyprland system.
# ==============================================================================

set -euo pipefail

# Text styling
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

log_info() { echo -e "${BLUE}::${RESET} ${BOLD}$1${RESET}"; }
log_success() { echo -e "${GREEN}✔${RESET} ${BOLD}$1${RESET}"; }
log_warn() { echo -e "${YELLOW}▲${RESET} ${YELLOW}$1${RESET}"; }
log_error() { echo -e "${RED}✖${RESET} ${RED}$1${RESET}" >&2; }

PURGE_DATA=false
ASSUME_YES=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Omarchy LLM Uninstaller

Usage:
  ./uninstall.sh [OPTIONS]

Options:
  -p, --purge         Completely remove stored API keys, configuration, and memories
  --keep-data         Preserve user settings and API keys in ~/.local/state (default)
  -y, --yes           Non-interactive mode; assume yes to confirmation prompts
  -h, --help          Show this help message and exit
EOF
  exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--purge)
      PURGE_DATA=true
      shift
      ;;
    --keep-data)
      PURGE_DATA=false
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

echo -e "${BOLD}${CYAN}───────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}${CYAN}           Omarchy LLM Uninstaller                ${RESET}"
echo -e "${BOLD}${CYAN}───────────────────────────────────────────────────${RESET}"

# Determine plugin ID
PLUGIN_ID="harsh.llm"
if [[ -f "$SCRIPT_DIR/manifest.json" ]]; then
  PLUGIN_ID=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/manifest.json')).get('id', 'harsh.llm'))" 2>/dev/null || echo "harsh.llm")
fi

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
TARGET_DIR="$PLUGINS_DIR/$PLUGIN_ID"
STATE_DIR="$HOME/.local/state/omarchy/plugins/$PLUGIN_ID"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.lua"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

if [[ "$ASSUME_YES" != true ]]; then
  echo -e "This will remove ${BOLD}$PLUGIN_ID${RESET} from your Omarchy shell and Hyprland keybindings."
  if [[ "$PURGE_DATA" == true ]]; then
    echo -e "${RED}Warning: --purge is set. All API keys and conversation memory will be deleted.${RESET}"
  fi
  read -r -p "Proceed with uninstall? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { log_error "Uninstallation aborted."; exit 1; }
fi

# 1. Disable in Omarchy Shell
log_info "Disabling plugin in Omarchy shell..."

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell setPluginEnabled "$PLUGIN_ID" false >/dev/null 2>&1 || true
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

# 2. Clean shell.json
if [[ -f "$SHELL_JSON" ]]; then
  log_info "Cleaning layout entries from $SHELL_JSON..."
  python3 - <<PYEOF
import json
import sys

path = "$SHELL_JSON"
plugin_id = "$PLUGIN_ID"

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    bar = data.get("bar", {})
    layout = bar.get("layout", {})
    modified = False

    for section in ("left", "center", "right"):
        if section in layout and isinstance(layout[section], list):
            original_len = len(layout[section])
            layout[section] = [item for item in layout[section] if not (isinstance(item, dict) and item.get("id") == plugin_id)]
            if len(layout[section]) != original_len:
                modified = True

    if "plugins" in data and isinstance(data["plugins"], list):
        orig_len = len(data["plugins"])
        data["plugins"] = [p for p in data["plugins"] if p != plugin_id]
        if len(data["plugins"]) != orig_len:
            modified = True

    if modified:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print("Removed plugin from shell.json.")
    else:
        print("No layout entries found in shell.json.")
except Exception as e:
    sys.stderr.write(f"Note: Could not update shell.json: {e}\n")
PYEOF
fi

# 3. Clean Hyprland Keybindings
if [[ -f "$HYPR_BINDINGS" ]]; then
  log_info "Removing keybindings from $HYPR_BINDINGS..."
  python3 - <<PYEOF
path = "$HYPR_BINDINGS"
begin_marker = "-- BEGIN OMARCHY-LLM KEYBINDINGS"
end_marker = "-- END OMARCHY-LLM KEYBINDINGS"

try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if begin_marker in content and end_marker in content:
        start = content.index(begin_marker)
        end = content.index(end_marker) + len(end_marker)
        if end < len(content) and content[end] == '\n':
            end += 1
        new_content = content[:start].rstrip() + "\n" + content[end:].lstrip()
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        print("Keybindings block removed.")
    else:
        print("No Omarchy LLM keybindings block found.")
except Exception as e:
    print(f"Failed to update keybindings: {e}")
PYEOF
  log_success "Cleaned Hyprland keybindings."
fi

# 4. Remove Plugin Files/Symlink
if [[ -L "$TARGET_DIR" ]]; then
  log_info "Removing symlink $TARGET_DIR..."
  rm -f "$TARGET_DIR"
  log_success "Removed plugin symlink."
elif [[ -d "$TARGET_DIR" ]]; then
  log_info "Removing plugin directory $TARGET_DIR..."
  rm -rf "$TARGET_DIR"
  log_success "Removed plugin directory."
else
  log_info "No plugin installation found at $TARGET_DIR."
fi

# 5. Handle State / Data
if [[ "$PURGE_DATA" == true ]]; then
  if [[ -d "$STATE_DIR" ]]; then
    log_info "Purging user data and keys at $STATE_DIR..."
    rm -rf "$STATE_DIR"
    log_success "Purged all plugin state files."
  fi
else
  if [[ -d "$STATE_DIR" ]]; then
    log_info "User configuration, API keys, and memory preserved at: ${BOLD}$STATE_DIR${RESET}"
    log_info "(To completely remove user data, re-run with: ${BOLD}./uninstall.sh --purge${RESET})"
  fi
fi

# 6. Rescan Shell
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
fi

# Send notification if available
if command -v omarchy-notification-send >/dev/null 2>&1; then
  omarchy-notification-send -g "󰚩" "Omarchy LLM Uninstalled" "Omarchy LLM has been removed from your desktop." >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send -i dialog-information "Omarchy LLM Uninstalled" "Omarchy LLM has been removed from your desktop." >/dev/null 2>&1 || true
fi

echo -e "${BOLD}${GREEN}───────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}${GREEN}       Uninstallation completed successfully!       ${RESET}"
echo -e "${BOLD}${GREEN}───────────────────────────────────────────────────${RESET}"
echo
