# Omarchy LLM

Native AI desktop companion, assistant, and autonomous agent for **Omarchy** on **Hyprland**.

Built on **Quickshell**, Omarchy LLM provides multi-provider streaming chat, system telemetry awareness, customizable desktop automation tools, persistent memory, and voice input (STT).

---

## Installation

You can install Omarchy LLM on any Omarchy Hyprland system using `install.sh`.

```bash
# Clone the repository (if not already cloned)
git clone https://github.com/your-username/omarchy-llm.git
cd omarchy-llm

# Run the installer
./install.sh
```

### Installation Options

| Option | Description |
| :--- | :--- |
| `-c, --copy` | Copy plugin files to `~/.config/omarchy/plugins/harsh.llm` (default) |
| `-s, --link` | Create a symbolic link instead of copying (recommended for development) |
| `--section <name>` | Place widget in `left`, `center`, or `right` bar section (default: `right`) |
| `--no-enable` | Install plugin without automatically enabling it in the bar layout |
| `--no-bindings` | Skip adding Hyprland shortcuts to `~/.config/hypr/bindings.lua` |
| `-y, --yes` | Non-interactive mode (auto-accept confirmation prompts) |
| `-h, --help` | Display help message and options |

---

## Uninstallation

To remove Omarchy LLM from your Omarchy shell and Hyprland configuration:

```bash
./uninstall.sh
```

### Uninstallation Options

| Option | Description |
| :--- | :--- |
| `--keep-data` | Preserve API keys and user memory in `~/.local/state/omarchy/plugins/harsh.llm` (default) |
| `-p, --purge` | Completely delete all stored keys, configuration, and memory files |
| `-y, --yes` | Non-interactive mode (skip confirmation prompts) |
| `-h, --help` | Display help message |

---

## Usage & Controls

- **Top Bar**: Click the **󰚩** icon in the status bar to toggle the assistant panel.
- **Keybindings**:
  - `SUPER + ALT + L`: Toggle panel
  - `SUPER + \`: Toggle panel
- **CLI / IPC Command**:
  ```bash
  omarchy-shell harsh.llm toggle
  ```
- **Voice Input (STT)**: Click or hold the microphone button in the chat view (supports PipeWire `pw-record` and OpenAI Whisper).
- **Persistent Data**: Configuration and API keys are stored securely (mode `0600`) under `~/.local/state/omarchy/plugins/harsh.llm/`.

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPLv3).

**License File**: See the [LICENSE](LICENSE) file for the full license text.

**External Dependencies & Their Licenses**:
- **OpenAI Python Library** - MIT License
- **OpenRouter API** - Apache 2.0 License
- **Anthropic Claude API** - Proprietary (API access)
- **Quickshell** - MIT License
- **PipeWire** - LGPL 2.1+
- **Whisper (OpenAI)** - MIT License
- **whisper-cpp** - MIT License

For more information about GPLv3, visit: https://www.gnu.org/licenses/gpl-3.0.html
