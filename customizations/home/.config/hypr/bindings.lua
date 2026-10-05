-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Open Dolphin instead of the default Nautilus file manager.
hl.unbind("SUPER + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = "dolphin" })

-- Launch the current user-installed Codex explicitly. The desktop launcher can
-- have a different PATH than the shell, where the older ~/.local copy wins.
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "omarchy-launch-tui --app-id=org.omarchy.agent @HOME@/.npm-global/bin/codex --ask-for-approval never")

-- Evo terminal and native desktop interfaces.
hl.unbind("SUPER + ALT + E")
o.bind("SUPER + ALT + E", "Evo TUI", "omarchy-launch-tui --app-id=org.evo.tui @HOME@/evo-Omarchy/.venv/bin/evo tui")
hl.unbind("SUPER + CTRL + ALT + E")
o.bind("SUPER + CTRL + ALT + E", "Evo Desktop", { launch = "@HOME@/evo-Omarchy/.venv/bin/evo desktop" })
