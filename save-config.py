#!/usr/bin/env python3
"""
Helper script for OmarchyLLM to safely manage configuration and API keys.
Ensures files have restricted permissions (0600) and writes atomically.
"""

import sys
import os
import json

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/plugins/harsh.llm")
CONFIG_FILE = os.path.join(STATE_DIR, "config.json")
KEYS_FILE = os.path.join(STATE_DIR, "keys.json")

def ensure_state_dir():
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)

def save_config(raw_payload=None):
    ensure_state_dir()
    if raw_payload is None:
        raw_payload = sys.stdin.read()
    try:
        data = json.loads(raw_payload)
    except Exception as e:
        sys.stderr.write(f"Invalid JSON: {e}\n")
        sys.exit(1)

    tmp = CONFIG_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, CONFIG_FILE)
    print("OK")

def save_key(provider, key):
    ensure_state_dir()
    keys = {}
    if os.path.isfile(KEYS_FILE):
        try:
            with open(KEYS_FILE, "r", encoding="utf-8") as f:
                keys = json.load(f)
        except Exception:
            keys = {}

    if key.strip():
        keys[provider] = key.strip()
    else:
        keys.pop(provider, None)

    tmp = KEYS_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(keys, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, KEYS_FILE)
    print("OK")

def main():
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: save-config.py [--save-config | --save-key <provider> <key>]\n")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "--save-config":
        payload = sys.argv[2] if len(sys.argv) > 2 else None
        save_config(payload)
    elif cmd == "--save-key" and len(sys.argv) >= 4:
        save_key(sys.argv[2], sys.argv[3])
    elif cmd == "--save-key" and len(sys.argv) == 3:
        save_key(sys.argv[2], "")
    else:
        sys.stderr.write(f"Unknown command: {cmd}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
