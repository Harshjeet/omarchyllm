#!/usr/bin/env python3
"""
OmarchyLLM Telemetry Gatherer
Fast, zero-dependency desktop and host telemetry collector for Hyprland + Omarchy.
"""

import os
import sys
import json
import subprocess
import platform
from datetime import datetime

def gather_telemetry():
    info = {
        "hostname": platform.node(),
        "os": "Omarchy",
        "kernel": platform.release(),
        "arch": platform.machine(),
        "shell": os.environ.get("SHELL", "bash"),
        "user": os.environ.get("USER", "user"),
        "desktop": "Hyprland (Omarchy Shell)",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }

    # 1. OS Pretty Name
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    info["os"] = line.split("=", 1)[1].strip().strip("\"")
                    break
    except Exception:
        pass

    # 2. CPU Model
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    info["cpu"] = line.split(":", 1)[1].strip()
                    break
    except Exception:
        info["cpu"] = "Unknown CPU"

    # 3. Memory Stats
    try:
        with open("/proc/meminfo") as f:
            mem = {}
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = parts[1].strip()
            total_mb = int(mem.get("MemTotal", "0").split()[0]) // 1024
            avail_mb = int(mem.get("MemAvailable", "0").split()[0]) // 1024
            info["memory"] = f"{avail_mb}MB available / {total_mb}MB total"
    except Exception:
        info["memory"] = "Unknown"

    # 4. Hyprland Active Window & Workspace
    try:
        active = subprocess.check_output(["hyprctl", "activewindow", "-j"], timeout=1).decode("utf-8")
        w = json.loads(active)
        if w.get("title"):
            info["activeWindow"] = f"{w.get('class', '')}: {w.get('title', '')}"
            info["workspace"] = str(w.get("workspace", {}).get("name", ""))
    except Exception:
        info["activeWindow"] = "None (Desktop)"
        info["workspace"] = "1"

    # 5. Active Omarchy Theme
    theme_readme = os.path.expanduser("~/.local/state/omarchy/current/theme/README.md")
    if os.path.isfile(theme_readme):
        try:
            with open(theme_readme) as f:
                first_line = f.readline().strip()
                if first_line.startswith("#"):
                    info["theme"] = first_line.lstrip("#").strip()
        except Exception:
            pass
    if "theme" not in info:
        info["theme"] = "Omarchy Default"

    # 6. Active Long-Term Memories
    mem_file = os.path.expanduser("~/.local/state/omarchy/plugins/harsh.llm/memory.json")
    if os.path.isfile(mem_file):
        try:
            with open(mem_file) as f:
                mem_list = json.load(f)
                if mem_list and isinstance(mem_list, list):
                    info["memories"] = "\n".join([f"{i}. {m}" for i, m in enumerate(mem_list, 1)])
        except Exception:
            pass

    return info

def main():
    info = gather_telemetry()
    print(json.dumps(info, indent=2))

if __name__ == "__main__":
    main()
