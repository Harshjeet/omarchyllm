#!/usr/bin/env python3
"""
OmarchyLLM Persistent Memory Store
Manages user preferences and memories across sessions.
Stores flat list of phrases in ~/.local/state/omarchy/plugins/harsh.llm/memory.json.
"""

import sys
import os
import json
import tempfile
import argparse

MEMORY_DIR = os.path.expanduser("~/.local/state/omarchy/plugins/harsh.llm")
MEMORY_FILE = os.path.join(MEMORY_DIR, "memory.json")

MAX_PHRASES = 100
MAX_PHRASE_LENGTH = 140

def load_memories():
    """Loads memories array from JSON file."""
    if not os.path.exists(MEMORY_FILE):
        return []
    try:
        with open(MEMORY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                return [str(item).strip() for item in data if str(item).strip()]
    except Exception as e:
        sys.stderr.write(f"OmarchyLLM: Failed to load memory.json: {e}\n")
    return []

def save_memories(memories):
    """Atomically saves memories array to JSON file."""
    os.makedirs(MEMORY_DIR, exist_ok=True)
    # Deduplicate and cap length
    clean = []
    seen = set()
    for m in memories:
        norm = " ".join(str(m).split()).strip()
        if not norm:
            continue
        if len(norm) > MAX_PHRASE_LENGTH:
            norm = norm[:MAX_PHRASE_LENGTH].strip()
        key = norm.lower()
        if key not in seen:
            seen.add(key)
            clean.append(norm)
        if len(clean) >= MAX_PHRASES:
            break

    tmp = tempfile.NamedTemporaryFile(mode="w", dir=MEMORY_DIR, delete=False, encoding="utf-8")
    try:
        json.dump(clean, tmp, indent=2)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp.name, MEMORY_FILE)
        return True
    except Exception as e:
        if os.path.exists(tmp.name):
            os.remove(tmp.name)
        sys.stderr.write(f"OmarchyLLM: Failed to save memory.json: {e}\n")
        return False

def add_memory(phrase):
    norm = " ".join(str(phrase).split()).strip()
    if not norm:
        return "Error: Empty memory phrase."
    
    memories = load_memories()
    key = norm.lower()
    for m in memories:
        if m.lower() == key:
            return f"Already remembered: '{m}'"
    
    memories.append(norm)
    if save_memories(memories):
        return f"Successfully remembered: '{norm}'"
    return "Error: Failed to persist memory to disk."

def remove_memory(target):
    target = str(target).strip()
    if not target:
        return "Error: Empty target to remove."
    
    memories = load_memories()
    if not memories:
        return "Memory is currently empty."

    # Try 1-based index
    if target.isdigit():
        idx = int(target) - 1
        if 0 <= idx < len(memories):
            removed = memories.pop(idx)
            save_memories(memories)
            return f"Successfully removed memory #{target}: '{removed}'"
        return f"Error: Invalid index #{target}. Available range: 1 to {len(memories)}."

    # Try matching text substring
    target_lower = target.lower()
    new_list = [m for m in memories if target_lower not in m.lower()]
    removed_count = len(memories) - len(new_list)

    if removed_count > 0:
        save_memories(new_list)
        return f"Successfully removed {removed_count} matching memory entry(ies)."
    
    return f"No memory entries matched '{target}'."

def clear_memories():
    if save_memories([]):
        return "Successfully cleared all saved memories."
    return "Error: Failed to clear memories."

def render_prompt_block():
    memories = load_memories()
    if not memories:
        return ""
    lines = ["## User Preferences & Long-Term Memories"]
    for i, m in enumerate(memories, 1):
        lines.append(f"{i}. {m}")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="OmarchyLLM Memory Manager")
    parser.add_argument("action", choices=["list", "add", "remove", "clear", "prompt"], help="Action to perform")
    parser.add_argument("phrase", nargs="?", default="", help="Memory phrase or index")
    parser.add_argument("--json", action="store_true", help="Output raw JSON for list")
    args = parser.parse_args()

    if args.action == "list":
        memories = load_memories()
        if args.json:
            print(json.dumps(memories, indent=2))
        else:
            if not memories:
                print("No memories stored yet.")
            else:
                for i, m in enumerate(memories, 1):
                    print(f"{i}. {m}")
    elif args.action == "add":
        print(add_memory(args.phrase))
    elif args.action == "remove":
        print(remove_memory(args.phrase))
    elif args.action == "clear":
        print(clear_memories())
    elif args.action == "prompt":
        print(render_prompt_block())

if __name__ == "__main__":
    main()
