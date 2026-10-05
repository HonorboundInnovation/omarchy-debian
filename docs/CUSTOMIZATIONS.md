# Captured desktop profile

The manifest records exported files and their origins. Original `@HOME@`
references are retained in the source export and rewritten during restore.

Included customizations:

- Neural Acid theme/background, generated active theme, and Foot template.
- Hyprland scaling, HDMI-A-2 at 1280×720/60 Hz, Dolphin binding, current Codex
  launcher, and Evo terminal/desktop bindings.
- Live cloned `malice.menu` with semantic SCU endpoints and local app fallback.
- Terminal theme integration, Kitty Shift+Enter, Neovim, GTK/KDE preferences,
  Dolphin preferences, menus/associations, Fcitx, UWSM, and Bluetooth A2DP.
- Chrome accessibility wrapper and selected launchers.
- Audio initialization/recovery, PipeWire ordering, idle config, stay-awake unit.
- Installed SDDM, resume, NVIDIA, font, PAM, systemd, and environment settings.

## Dependencies and hardware

Evo bindings require `~/evo-Omarchy/.venv/bin/evo`; Codex requires
`~/.npm-global/bin/codex`. These application sources and environments remain in
their separate projects. The default agent is `codex`. The custom menu remains
an ordinary Omarchy menu without SCU; semantic control requires SCU separately.
Chrome must be installed for its wrapper. The Arch launcher needs its Distrobox.

Audio scripts target Intel SOF HDA at the local PCI address, ALSA card 1, and Speaker.
The global recovery script can reset WirePlumber state and restart audio. They
are stored for this hardware and are not executed by capture or restore.
On this machine `sof-hda-alsa-init.service` and `stay-awake.service` were enabled;
the user `fix-audio-output.service` was disabled and the global audio unit was
enabled. Restore does not automatically enable units.

The export preserves actual idle settings: Hypridle has no timers; stay-awake
inhibits idle/sleep; shell.json separately retains 150-second screensaver and
300-second lock values. Decide desired behavior before enabling power units
elsewhere. Resume contains the original swap UUID. NVIDIA settings and SDDM's
KWin Wayland greeter are machine-specific. System exports are reference-only.

The portable snapshot bridge needs explicit configuration. If activating it on
this machine, run `./bridge/activate-system.sh --snapshot-mount /mnt/storage`.
This collection did not activate that bridge or change the running system.

## Scope

The repository collects the Omarchy/Debian desktop and related hardware fixes.
It excludes browser data, account credentials, OpenClaw/HBSE services, unrelated
application projects, the Arch container home, installed binaries, and build
caches. Omarchy upstream is fetched at its pinned revision; local changes are
exported separately. Samples, backup files, bookmarks, cached input layouts,
and Dolphin directory history are omitted.
