#!/usr/bin/env bash

# ==============================================================================
# Omarchy LLM Installer
# Installs and enables Omarchy LLM on any Omarchy Hyprland system.
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

# Default configuration
INSTALL_MODE="copy"        # "copy" or "link"
ENABLE_PLUGIN=true
ADD_BINDINGS=true
ASSUME_YES=false
CUSTOM_SECTION=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Omarchy LLM Installer

Usage:
  ./install.sh [OPTIONS]

Options:
  -c, --copy          Copy files to Omarchy plugins directory (default)
  -s, --link, --symlink
                      Create a symbolic link instead of copying (ideal for development)
  --section <name>    Target bar section (left, center, or right; default: right)
  --no-enable         Do not enable or place the widget into Omarchy bar layout
  --no-bindings       Do not add Hyprland keybindings into ~/.config/hypr/bindings.lua
  -y, --yes           Automatic yes to prompts; run non-interactively
  -h, --help          Show this help message and exit

Keybindings configured by default:
  SUPER + ALT + L     Toggle Omarchy LLM Assistant
  SUPER + \\           Toggle Omarchy LLM Assistant
EOF
  exit 0
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--copy)
      INSTALL_MODE="copy"
      shift
      ;;
    -s|--link|--symlink)
      INSTALL_MODE="link"
      shift
      ;;
    --section)
      [[ -n "${2:-}" ]] || { log_error "--section requires an argument (left, center, or right)"; exit 1; }
      CUSTOM_SECTION="$2"
      shift 2
      ;;
    --no-enable)
      ENABLE_PLUGIN=false
      shift
      ;;
    --no-bindings)
      ADD_BINDINGS=false
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
echo -e "${BOLD}${CYAN}            Omarchy LLM Installer                  ${RESET}"
echo -e "${BOLD}${CYAN}───────────────────────────────────────────────────${RESET}"

# 1. Environment & Dependency Checks
log_info "Verifying system prerequisites..."

if ! command -v python3 >/dev/null 2>&1; then
  log_error "Python 3 is required but was not found. Please install python3."
  exit 1
fi

OMARCHY_DETECTED=false
if [[ -d "$HOME/.config/omarchy" || -d "/usr/share/omarchy" ]] || command -v omarchy >/dev/null 2>&1; then
  OMARCHY_DETECTED=true
fi

if [[ "$OMARCHY_DETECTED" != true ]]; then
  log_warn "Omarchy configuration not detected in standard paths (~/.config/omarchy or /usr/share/omarchy)."
  if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "Continue installation anyway? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { log_error "Installation cancelled."; exit 1; }
  fi
else
  log_success "Omarchy desktop environment detected."
fi

# Check optional helpers for enhanced experience
if ! command -v pw-record >/dev/null 2>&1; then
  log_warn "pw-record (pipewire) not found; microphone voice input will require fallback or Qt multimedia."
fi

# Check offline Whisper STT
if command -v whisper-cli >/dev/null 2>&1 || command -v whisper-cpp >/dev/null 2>&1; then
  log_success "Offline Whisper engine detected (whisper-cpp)."
  MODEL_FOUND=false
  for dir in "$HOME/.local/share/whisper-cpp" "$HOME/.cache/whisper" "$HOME/.cache/whisper-cpp"; do
    if compgen -G "$dir/ggml-*.bin" >/dev/null 2>&1; then
      MODEL_FOUND=true
      break
    fi
  done
  if [[ "$MODEL_FOUND" == true ]]; then
    log_success "Offline Whisper model ready in ~/.local/share/whisper-cpp."
  else
    log_warn "No GGML model found in ~/.local/share/whisper-cpp/."
    log_info "Downloading ggml-base.en.bin (~142MB) for offline speech-to-text..."
    mkdir -p "$HOME/.local/share/whisper-cpp"
    curl -L -o "$HOME/.local/share/whisper-cpp/ggml-base.en.bin" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" || \
      log_warn "Failed to download model automatically. You can download it later in Settings."
  fi
fi

# 2. Read manifest data
MANIFEST_PATH="$SCRIPT_DIR/manifest.json"
if [[ ! -f "$MANIFEST_PATH" ]]; then
  log_error "manifest.json not found in $SCRIPT_DIR."
  exit 1
fi

PLUGIN_ID=$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH')).get('id', 'harsh.llm'))")
DEFAULT_SECTION=$(python3 -c "import json; print(json.load(open('$MANIFEST_PATH')).get('barWidget', {}).get('defaultSection', 'right'))")
SECTION="${CUSTOM_SECTION:-$DEFAULT_SECTION}"

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
TARGET_DIR="$PLUGINS_DIR/$PLUGIN_ID"
STATE_DIR="$HOME/.local/state/omarchy/plugins/$PLUGIN_ID"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.lua"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

log_info "Plugin ID: ${BOLD}$PLUGIN_ID${RESET}"
log_info "Target directory: ${BOLD}$TARGET_DIR${RESET}"
log_info "Installation mode: ${BOLD}$INSTALL_MODE${RESET}"

mkdir -p "$PLUGINS_DIR"

# 3. Perform Copy or Symlink
if [[ "$SCRIPT_DIR" == "$TARGET_DIR" ]]; then
  log_info "Running directly from plugin destination; preserving existing files."
else
  if [[ "$INSTALL_MODE" == "link" ]]; then
    if [[ -e "$TARGET_DIR" && ! -L "$TARGET_DIR" ]]; then
      BACKUP_DIR="${TARGET_DIR}.bak.$(date +%s)"
      log_warn "Moving existing non-symlink plugin directory to $BACKUP_DIR"
      mv "$TARGET_DIR" "$BACKUP_DIR"
    elif [[ -L "$TARGET_DIR" ]]; then
      rm -f "$TARGET_DIR"
    fi
    ln -sfn "$SCRIPT_DIR" "$TARGET_DIR"
    log_success "Symlinked $SCRIPT_DIR -> $TARGET_DIR"
  else
    if [[ -L "$TARGET_DIR" ]]; then
      log_info "Replacing previous symlink with directory copy..."
      rm -f "$TARGET_DIR"
    fi
    mkdir -p "$TARGET_DIR"

    # Use rsync if available, otherwise cp
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude='.git' \
        --exclude='.github' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.pytest_cache' \
        --exclude='tests' \
        --exclude='scratch' \
        "$SCRIPT_DIR/" "$TARGET_DIR/"
    else
      # Clean copy via cp
      cp -a "$SCRIPT_DIR"/. "$TARGET_DIR"/
      rm -rf "$TARGET_DIR/.git" "$TARGET_DIR/__pycache__" "$TARGET_DIR"/*.pyc
    fi
    log_success "Copied plugin files into $TARGET_DIR"
  fi
fi

# 4. Set Permissions
log_info "Ensuring correct file permissions..."
find "$TARGET_DIR" -maxdepth 2 -type f -name "*.py" -exec chmod +x {} +
chmod +x "$TARGET_DIR/install.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/uninstall.sh" 2>/dev/null || true

# Ensure state directory exists with secure permissions (0700)
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
log_success "State directory secured at $STATE_DIR (0700)"

# 5. Validate Plugin if Omarchy validator is available
VALIDATE_TARGET="$TARGET_DIR"
if [[ -L "$TARGET_DIR" ]]; then
  VALIDATE_TARGET="$SCRIPT_DIR"
fi

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  log_info "Validating plugin manifest via omarchy-plugin-validate..."
  if omarchy-plugin-validate "$VALIDATE_TARGET"; then
    log_success "Plugin structure and manifest validated successfully."
  else
    log_warn "Plugin validation warning (check manifest properties)."
  fi
elif command -v omarchy >/dev/null 2>&1 && omarchy plugin validate "$VALIDATE_TARGET" >/dev/null 2>&1; then
  log_success "Plugin validated via omarchy CLI."
fi

# 6. Enable in Omarchy Shell
if [[ "$ENABLE_PLUGIN" == true ]]; then
  log_info "Registering and enabling plugin in Omarchy shell (section: $SECTION)..."

  SHELL_RUNNING=false
  if command -v omarchy-shell >/dev/null 2>&1; then
    if omarchy-shell -q shell ping >/dev/null 2>&1; then
      SHELL_RUNNING=true
    fi
  fi

  if [[ "$SHELL_RUNNING" == true ]]; then
    # Rescan plugins first
    omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

    # Enable via omarchy-plugin-enable / omarchy plugin enable
    if command -v omarchy-plugin-enable >/dev/null 2>&1; then
      omarchy-plugin-enable "$PLUGIN_ID" --section "$SECTION" >/dev/null 2>&1 || true
    elif command -v omarchy >/dev/null 2>&1; then
      omarchy plugin enable "$PLUGIN_ID" --section "$SECTION" >/dev/null 2>&1 || true
    else
      omarchy-shell -q shell enablePlugin "$PLUGIN_ID" "{\"section\":\"$SECTION\"}" >/dev/null 2>&1 || true
    fi
    log_success "Plugin registered and enabled in running Omarchy shell."
  fi

  # Ensure ~/.config/omarchy/shell.json has the widget placed
  if [[ -f "$SHELL_JSON" ]]; then
    python3 - <<PYEOF
import json
import sys

path = "$SHELL_JSON"
plugin_id = "$PLUGIN_ID"
section = "$SECTION"

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    bar = data.setdefault("bar", {})
    layout = bar.setdefault("layout", {})
    sec_list = layout.setdefault(section, [])

    # Check if already present in this section
    exists = any(isinstance(item, dict) and item.get("id") == plugin_id for item in sec_list)
    if not exists:
        # Also remove from other sections if accidentally placed multiple times
        for s in ("left", "center", "right"):
            if s != section and s in layout and isinstance(layout[s], list):
                layout[s] = [item for item in layout[s] if not (isinstance(item, dict) and item.get("id") == plugin_id)]
        sec_list.append({"id": plugin_id})
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print("Updated shell.json layout.")
    else:
        print("Plugin is already present in shell.json layout.")
except Exception as e:
    sys.stderr.write(f"Note: Could not update shell.json: {e}\n")
PYEOF
  fi
fi

# 7. Configure Hyprland Keybindings
if [[ "$ADD_BINDINGS" == true ]]; then
  log_info "Configuring Hyprland keybindings..."
  if [[ -f "$HYPR_BINDINGS" ]]; then
    python3 - <<PYEOF
import os

path = "$HYPR_BINDINGS"
plugin_id = "$PLUGIN_ID"

block = f"""-- BEGIN OMARCHY-LLM KEYBINDINGS
if type(o) == "table" and type(o.bind) == "function" then
  o.bind("SUPER + ALT + L", "Omarchy LLM Assistant", "omarchy-shell {plugin_id} toggle")
  o.bind("SUPER + BACKSLASH", "Omarchy LLM Assistant", "omarchy-shell {plugin_id} toggle")
elseif type(hl) == "table" and type(hl.bind) == "function" then
  hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd("omarchy-shell {plugin_id} toggle"))
  hl.bind("SUPER + BACKSLASH", hl.dsp.exec_cmd("omarchy-shell {plugin_id} toggle"))
end
-- END OMARCHY-LLM KEYBINDINGS
"""

try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    begin_marker = "-- BEGIN OMARCHY-LLM KEYBINDINGS"
    end_marker = "-- END OMARCHY-LLM KEYBINDINGS"

    if begin_marker in content and end_marker in content:
        start = content.index(begin_marker)
        end = content.index(end_marker) + len(end_marker)
        # Check for trailing newline
        if end < len(content) and content[end] == '\n':
            end += 1
        new_content = content[:start] + block + content[end:]
    else:
        new_content = content.rstrip() + "\n\n" + block

    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print("Hyprland keybindings updated in " + path)
except Exception as e:
    print("Failed to update keybindings: " + str(e))
PYEOF
    log_success "Keybindings registered (SUPER+ALT+L and SUPER+\\)"
  else
    log_warn "$HYPR_BINDINGS not found; skipping keybinding injection."
  fi
fi

# 8. Reload / Rescan
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
fi

# Send desktop notification if available
if command -v omarchy-notification-send >/dev/null 2>&1; then
  omarchy-notification-send -g "󰚩" "Omarchy LLM Installed" "AI assistant is ready on your top bar or press Super+Alt+L." >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send -i dialog-information "Omarchy LLM Installed" "AI assistant is ready on your top bar or press Super+Alt+L." >/dev/null 2>&1 || true
fi

echo -e "${BOLD}${GREEN}───────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}${GREEN}        Installation completed successfully!        ${RESET}"
echo -e "${BOLD}${GREEN}───────────────────────────────────────────────────${RESET}"
echo -e "You can toggle the assistant using:"
echo -e "  • Top Bar widget: Click ${BOLD}󰚩${RESET} icon in the $SECTION section"
echo -e "  • Keyboard shortcut: ${BOLD}SUPER + ALT + L${RESET} or ${BOLD}SUPER + \\\\${RESET}"
echo -e "  • Terminal IPC: ${BOLD}omarchy-shell $PLUGIN_ID toggle${RESET}"
echo
