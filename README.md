# Omarchy on Debian 13

This installer turns a fresh Debian 13 (Trixie) system into an Omarchy-style Hyprland desktop. It installs Omarchy Quattro's released shell, themes, Quickshell UI, Hyprland configuration, keybindings, login theme, user services, and application defaults, then adapts package and system operations to Debian.

The Omarchy files are pinned to [v4.0.4](https://github.com/omacom/omarchy/tree/v4.0.4) at commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`. This is an independent Debian installer, not an official Omarchy release.

## Install

Run the script as your regular desktop user. It uses `sudo` for system changes and requires an internet connection.

```bash
chmod +x install-omarchy-debian.sh
./install-omarchy-debian.sh
```

Source builds for companion projects run by default. To skip those optional compilations:

```bash
./install-omarchy-debian.sh --skip-source-builds
```

That option skips compilation only. The script still installs pinned release assets such as the Nerd Font, LocalSend, Mise when Debian does not provide it, `ufw-docker`, and the Omarchy Neovim configuration.

When it finishes, log out, choose **Omarchy on Debian** in the session menu, and log back in. It runs Omarchy's first-user setup before exiting. It does not partition disks, change the bootloader, enable automatic login, or reboot. Existing user configs that it replaces are moved into `~/.config/omarchy-debian-backup-*`.

The installer enables Debian's official `contrib` and `non-free` components for Trixie, updates, security, and backports, and adds the `trixie-backports` source when it is not already enabled. Debian 13's standard installer source includes `non-free-firmware`; the installer leaves that existing setting intact. It installs Debian-maintained backports for [Hyprland](https://packages.debian.org/trixie-backports/hyprland), [Quickshell](https://packages.debian.org/trixie-backports/x11/quickshell), [UWSM](https://packages.debian.org/stable-backports/uwsm), and the [Hyprland portal](https://packages.debian.org/trixie-backports/xdg-desktop-portal-hyprland).

## Included

- Omarchy's Quickshell UI, themes, wallpapers, Hyprland Lua configuration, shell commands, and default keybindings from the pinned release.
- Debian session startup through UWSM, the Omarchy SDDM theme and PAM service, fontconfig and Fcitx environment settings, the terminal registration, and Omarchy's user/system service units.
- Debian equivalents for the upstream base package manifest: desktop, audio, fonts, development, media, printing, networking, file-manager, storage, and container tools. Package aliases adapt common Arch names such as `networkmanager`, `nvim`, `fd`, `docker-compose`, `tesseract`, and `qemu-user-static-binfmt` to Debian package names.
- Debian adapters for Omarchy package install, remove, update, version, and presence commands. `omarchy pkg install` searches Debian's package list; updates use APT. Pacman compatibility is read-only and handles common installed-package queries. AUR installation is unavailable on Debian.
- The pinned Omarchy Neovim/LazyVim configuration. Existing Neovim config is backed up; LazyVim plugin downloads happen on the first Neovim launch.
- Omarchy's JetBrainsMono Nerd Font and its own font assets. LocalSend uses its upstream Debian package when Trixie has no package. Mise and the UFW/Docker helper are installed from pinned upstream releases if needed.
- System defaults for `systemd-oomd`, nofile limits, and zram generation. The installer enables NetworkManager, Bluetooth, power profiles, printing, mDNS, Docker's socket, and systemd-oomd when those units are present.

The script compiles portable Omarchy companion projects when their Debian build dependencies are available: Aether (only when Go and Node meet upstream minimum versions), asdcontrol, cliamp, Herdr, OmaCalc, OmaCut, OmaWrite, OmaSnap, OWE and its Quickshell lock-feed plugin, ttfx, Tensaku, tzupdate, the Elsewhen Quickshell plugin, and the Hyprland preview share picker. It also has pinned upstream source fallbacks for `dua-cli`, GPU Screen Recorder, lazydocker, Moonlight Qt, `usage`, and `tobi-try` when their Debian package did not leave the corresponding command installed. `dua-cli` and `usage` build from their GitHub source checkouts; the other builders use pinned GitHub revisions, upstream versioned Go sources, or a checksum-verified source archive. Failed optional builds are logged and do not stop the desktop setup.

The source build log is `~/.cache/omarchy-debian/source-builds.log`. Package candidates that are missing or fail installation, along with source-fallback outcomes, are recorded in `~/.cache/omarchy-debian/package-install-report.log`; failed package groups are retried one package at a time. The required Hyprland, Quickshell, UWSM, and portal packages stop installation with a specific error if Debian cannot provide them. GPU Screen Recorder is built without installing privileged capture capabilities or changing NVIDIA/kernel settings; Wayland capture therefore depends on portal and hardware support. Moonlight follows the upstream Linux build steps and Debian dependency list ([upstream build notes](https://github.com/moonlight-stream/moonlight-qt#building)).

## Debian-specific limits

- This configures Debian in place; it does not make a bootable Omarchy-like ISO. Debian's kernel, firmware, package sources, init system, and bootloader remain in control. There is no Omarchy custom kernel, Limine setup, Snapper snapshot integration, disk encryption/partitioning flow, or Arch hardware-detection installer.
- The Omarchy Plymouth theme files are installed, but the active boot splash is not changed. Existing display-manager configuration is preserved when it is not managed by this installer.
- `yay`, the AUR, `pacman-contrib`/`expac` metadata behavior, and `kernel-modules-hook` are Arch-specific. The package menu and update adapters use APT equivalents where possible; Debian handles kernel module rebuilds through its own mechanisms.
- Omarchy lists a .NET runtime package, but Debian's standard Trixie repositories do not provide that Arch package. The script does not add Microsoft's repository. Obsidian and other proprietary applications are installed only if they already exist in the enabled Debian sources.
- GPU drivers and firmware availability depend on hardware and Debian's `non-free-firmware` component. The installer adds `contrib` and `non-free` from Debian's official archive; it does not add third-party repositories or install proprietary GPU drivers. The UFW/Docker helper is installed without enabling UFW or changing firewall rules.
- Debian's Hyprland and Quickshell versions can differ from Omarchy's. Some optional packages may not exist for the machine's architecture or currently enabled repositories; those are reported and skipped.

For reference, the upstream [Omarchy base package manifest](https://github.com/omacom/omarchy/blob/v4.0.4/install/omarchy-base.packages) defines the core package set that this script adapts.
