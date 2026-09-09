#!/usr/bin/env python3
"""
OmarchyLLM Skill Loader
Discovers and loads specialized SKILL.md instruction files from plugin or user skill directories.
"""

import sys
import os
import argparse

SKILL_DIRS = [
    os.path.expanduser("~/.config/omarchy/plugins/harsh.llm/skills"),
    os.path.expanduser("~/.config/omarchy/skills"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "skills")
]

def list_skills():
    """Finds all available skills across directories."""
    skills = {}
    for d in SKILL_DIRS:
        if os.path.isdir(d):
            try:
                for entry in os.listdir(d):
                    skill_path = os.path.join(d, entry, "SKILL.md")
                    if os.path.isfile(skill_path) and entry not in skills:
                        # Extract first header as summary
                        summary = entry
                        try:
                            with open(skill_path, "r", encoding="utf-8") as f:
                                for line in f:
                                    line = line.strip()
                                    if line.startswith("# "):
                                        summary = line.lstrip("# ").strip()
                                        break
                        except Exception:
                            pass
                        skills[entry] = {
                            "name": entry,
                            "summary": summary,
                            "path": skill_path
                        }
            except Exception:
                pass
    return skills

def load_skill(name):
    """Loads and returns the content of SKILL.md for a given skill name."""
    clean_name = name.strip().lower()
    skills = list_skills()
    if clean_name not in skills:
        available = ", ".join(sorted(skills.keys())) if skills else "none"
        return f"Error: Skill '{name}' not found. Available skills: {available}"
    
    skill_info = skills[clean_name]
    try:
        with open(skill_info["path"], "r", encoding="utf-8") as f:
            content = f.read()
            return f"--- Skill Loaded: {clean_name} ---\n\n{content}"
    except Exception as e:
        return f"Error loading skill '{name}': {str(e)}"

def main():
    parser = argparse.ArgumentParser(description="OmarchyLLM Skill Manager")
    parser.add_argument("action", choices=["list", "load"], help="Action to perform")
    parser.add_argument("name", nargs="?", default="", help="Skill name")
    args = parser.parse_args()

    if args.action == "list":
        skills = list_skills()
        if not skills:
            print("No skills found.")
        else:
            print("Available skills:")
            for k, v in sorted(skills.items()):
                print(f"- {k}: {v['summary']}")
    elif args.action == "load":
        if not args.name:
            print("Error: Specify a skill name to load.")
            sys.exit(1)
        print(load_skill(args.name))

if __name__ == "__main__":
    main()
