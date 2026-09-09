# Arch Linux System Maintenance & Package Management Skill

This skill provides expert instructions and best practices for managing Arch Linux systems.

## Key Guidelines

1. **Package Installation**:
   - Official repositories: `sudo pacman -S <package>`
   - AUR packages: `yay -S <package>` (never run `yay` as root with sudo).
   - System updates: `sudo pacman -Syu` (official) or `yay -Syu` (full system including AUR).

2. **Package Queries**:
   - Search repos: `pacman -Ss <keyword>`
   - Inspect installed package: `pacman -Qi <package>`
   - List files owned by package: `pacman -Ql <package>`
   - Find package owning a file: `pacman -Qo /path/to/file`

3. **System Hygiene & Maintenance**:
   - Clean pacman cache: `sudo paccache -r` or `yay -Sc`
   - List orphan packages: `pacman -Qtdq`
   - Remove orphan packages safely: `sudo pacman -Rns $(pacman -Qtdq)`
   - Check failed systemd services: `systemctl --failed`
   - Inspect journal errors: `journalctl -p 3 -xb`

4. **Safety Warnings**:
   - Never use `pacman -Sy` alone without `u` (partial upgrades can break system libraries).
   - Avoid `--noconfirm` when installing unfamiliar AUR packages.
