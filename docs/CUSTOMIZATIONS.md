# Captured desktop profile

The manifest records logical file origins without the capturing user's home
path. Exported text uses `@HOME@`, expanded to the selected home during restore;
home symlinks are relative. Exported files are templates for the restore tool.

Included customizations:

- Neural Acid theme/background, generated active theme, and Foot template.
- Hyprland scaling, HDMI-A-2 at 1280×720/60 Hz, Dolphin binding, current Codex
  launcher, and Evo terminal/desktop bindings.
- Live cloned `malice.menu` with semantic SCU endpoints and local app fallback.
- Terminal theme integration, Kitty Shift+Enter, Neovim, GTK/KDE preferences,
  Dolphin preferences, menus/associations, Fcitx, UWSM, and Bluetooth A2DP.
- Chrome accessibility wrapper and selected launchers.
- Audio initialization, PipeWire ordering, idle config, stay-awake unit.
- Installed SDDM, NVIDIA, font, PAM, systemd, and environment settings.

## Dependencies and hardware

Evo bindings require `~/evo-Omarchy/.venv/bin/evo`; Codex requires
`~/.npm-global/bin/codex`. These application sources and environments remain in
their separate projects. The default agent is `codex`. The custom menu remains
an ordinary Omarchy menu without SCU; semantic control requires SCU separately.
Chrome must be installed for its wrapper. The Arch launcher needs its Distrobox.

Audio initialization targets Intel SOF HDA and ALSA card 1. Check these choices
before restoring with `--hardware`. The user/global audio recovery helpers and
their paired units are excluded because they contain a host-specific PCI
address. Existing live helpers are unaffected. On this machine
`sof-hda-alsa-init.service` and `stay-awake.service` were enabled. Restore does
not automatically enable units.

The export preserves actual idle settings: Hypridle has no timers; stay-awake
inhibits idle/sleep; shell.json separately retains 150-second screensaver and
300-second lock values. Decide desired behavior before enabling power units
elsewhere. Resume files are excluded because they contain filesystem UUIDs;
configure hibernation for the destination machine separately. NVIDIA settings
and SDDM's KWin Wayland greeter are machine-specific. System exports are reference-only.

The portable snapshot bridge needs explicit configuration. If activating it on
this machine, run `./bridge/activate-system.sh --snapshot-mount /mnt/storage`.
This collection did not activate that bridge or change the running system.

## Scope

The repository collects the Omarchy/Debian desktop and related hardware fixes.
It excludes browser data, account credentials, OpenClaw/HBSE services, unrelated
application projects, the Arch container home, installed binaries, and build
caches. Omarchy upstream is fetched at its pinned revision; local changes are
exported separately. Samples, backup files, bookmarks, cached input layouts,
and Dolphin/KDE directory history are omitted. The complete staged export is
scanned for recognizable credentials and private host identifiers before it
replaces the previous capture. `check` and `restore` enforce the same scan;
review diffs as well, since pattern detection is not exhaustive.
