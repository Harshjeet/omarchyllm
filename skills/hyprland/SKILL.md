# Hyprland Compositor & Window Management Skill

This skill provides expert instructions and CLI idioms for the Hyprland Wayland compositor on Arch Linux.

## Key Guidelines

1. **Hyprland Architecture**:
   - Having Lua configuration
   - Configuration file: `~/.config/hypr/hyprland.lua`
   - IPC control binary: `hyprctl`
   - Reload configuration live: `hyprctl reload`

2. **Common `hyprctl` Queries**:
   - Active focused window JSON: `hyprctl activewindow -j`
   - List all open clients / windows: `hyprctl clients -j`
   - List active workspaces: `hyprctl workspaces -j`
   - List connected monitors: `hyprctl monitors -j`
   - Check version & build: `hyprctl version`

3. **Window Dispatchers**:
   - Toggle floating: `hyprctl dispatch togglefloating`
   - Close active window: `hyprctl dispatch killactive`
   - Switch workspace: `hyprctl dispatch workspace <number>`
   - Move active window to workspace: `hyprctl dispatch movetoworkspace <number>`

4. **Window Rules (v2)**:
   - Floating rule: `windowrulev2 = float,class:^(pavucontrol)$`
   - Center rule: `windowrulev2 = center,class:^(imv)$`
   - Opacity rule: `windowrulev2 = opacity 0.90 0.80,class:^(kitty)$`
