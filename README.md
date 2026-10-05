# Omarchy on Debian

This is my Debian 13 Omarchy installer, built mostly for me, as a test of 
a theory. and eventually turned into my full time desktop environment. I now
have this running on my laptop and my desktop. I'm releasing this as a 
curiosity that turned into something I genuinely enjoy using.

APT/Arch bridge, Neural Acid theme, custom menu, and desktop configuration.
Omarchy is pinned to v4.0.4, commit
`c668141e9c42b13c80c9ca4ea108e11708c5e8a5`. This is an independent Debian port.

## Installation

Keep the checkout in a permanent location: bridge activation links commands
from `~/.local/bin` back into this repository. Run as your desktop user:

```sh
./install.sh
# Optional: snapshots on an existing separate mounted filesystem
./install.sh --snapshot-mount /mnt/storage
# Optional: skip companion-app compilations
./install.sh --skip-source-builds
```

Installation changes Debian packages, system defaults, and the login session.
Replaced user configurations are backed up. Log out, select **Omarchy on Debian**,
and log back in. Downloads need internet access; this is not an offline mirror.
APT owns the host OS, drivers, PAM, shared libraries, and services. Arch/AUR apps
run in a rootless Podman Distrobox. `omarchy update` updates both. Source channels
stage releases for review; new releases still need Debian port/migration work.
Factory reset remains disabled.

## Restore this desktop's customizations

Preview the profile, then explicitly apply it:

```sh
python3 scripts/customizations.py restore
python3 scripts/customizations.py restore --apply
```

This restores Hyprland settings, the custom `malice.menu` plugin, Neural Acid and
its generated theme state, terminal and Neovim settings, GTK/KDE preferences,
file associations, UWSM/Fcitx, Bluetooth configuration, and selected launchers.
Existing files are backed up under
`~/.local/state/omarchy-debian/restore-backups/`. Home-directory references are
rewritten for the restoring user. Log out and back in to load restored settings.

The HDMI override, Evo bindings, Codex path, Chrome accessibility wrapper, and
SCU integration reflect this machine. Read [profile notes](docs/CUSTOMIZATIONS.md)
before restoring on another machine. User audio/power scripts and units are
included through an additional switch:

```sh
python3 scripts/customizations.py restore --hardware
python3 scripts/customizations.py restore --hardware --apply
```

Units are copied but not enabled or started automatically. Root-owned files in
`customizations/system/` are reference material and are never installed by
restore. NVIDIA, audio initialization, and SDDM settings must match the hardware.
Host-specific audio recovery helpers and resume files are excluded from capture.

Refresh the export after editing your live desktop, then review the diff:

```sh
python3 scripts/customizations.py capture
python3 scripts/customizations.py check
```

Capture uses an explicit desktop allowlist. Credentials, browser profiles,
agent account settings, unrelated app services, logs, caches, backups, bookmarks,
and Dolphin/KDE directory history are excluded. `manifest.json` records logical
sources such as `home:.config/hypr/bindings.lua`, modes, symlinks, checksums, and
the upstream source revision. Exported text uses `@HOME@` for the captured home;
restore expands it to the destination home. Home symlinks are stored relatively.
Use restore to materialize these templates before using the exported configs.

Capture scans the entire staged tree, including upstream patches, extra files,
binary strings, filenames, and symlink targets, before replacing the previous
export. Detected keys, private keys, credential assignments/URLs, authorization
headers, cookies, filesystem UUID references, absolute user paths, and audio PCI
addresses abort capture and leave the previous export intact. `check` and
`restore` run the same scan. Errors report paths and rule names without printing
matched values. Fix the source file or remove it from the allowlist and retry;
there is no scanner bypass switch. Pattern detection cannot identify every
possible secret, so continue reviewing the diff before publishing. Existing Git
history is unaffected by a new capture. Upstream recovery overlays retain exact
bytes; private paths in them must be fixed at the source before capture succeeds.

## Files

| Path | Purpose |
| --- | --- |
| `install.sh` | Base installation and bridge activation |
| `install-omarchy-debian.sh` | Comprehensive pinned Debian installer and runtime fixes |
| `install-omarchy-debian-missing.sh` | Optional supplemental components; use `--list` or `--only NAME` |
| `omarchy-debian-runtime.patch` | mawk, notification QML, and SDDM session fixes |
| `omarchy-debian-assets/` | Neural Acid source assets and Foot template |
| `bridge/` | Package, update, snapshot, boot, and channel adapters with tests |
| `adapters/pacman` | Installed Debian-only package query, filtering actual installed packages |
| `skills/` | Maintained Debian Omarchy and crash-diagnosis skills |
| `customizations/home/` | Desktop profile, relative to the user's home |
| `customizations/hardware/` | User audio/power files, relative to home |
| `customizations/system/` | System reference configuration |
| `customizations/upstream/` | Installed tracked overlay and Debian-only additions |
| `scripts/` | Capture, restore, and validation tools |

The supplemental installer can add Microsoft's .NET feed and optional
Flatpak/upstream apps; the default installer does not run it. The installed
upstream overlay is an exact reference/recovery export; the base installer is
the maintained deployment path. Do not apply both overlays to the same tree.

The base installer installs maintained Debian skills and links missing agent
discovery entries, preserving existing independent skills.
`./install-codex-skills.sh` supports installing just the Codex skills.

## Validation

```sh
./scripts/check.sh
# Optional lint when ShellCheck is available
SHELLCHECK=/path/to/shellcheck ./scripts/check.sh
```

Checks cover shell/Python/Lua syntax, capture checksums and privacy rejection,
bridge command routing, snapshot guards, restore backups/relocation, and runtime patch application when
the pinned upstream checkout is present. A complete clean-machine installation
and Timeshift restore are not yet tested.

See [source reconciliation](docs/PROVENANCE.md), [profile notes](docs/CUSTOMIZATIONS.md),
and [attribution](docs/THIRD_PARTY.md). The package gap report describes the
original September 22 installation, not current package availability.
