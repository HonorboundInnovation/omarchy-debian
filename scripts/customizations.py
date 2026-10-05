#!/usr/bin/env python3
"""Capture and restore the desktop profile without copying account credentials."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "customizations"
CONFIGS = (
    "hypr", "omarchy", "alacritty", "foot", "kitty", "ghostty", "uwsm",
    "environment.d", "menus", "wireplumber", "pipewire", "btop", "lazygit",
    "nvim", "starship.toml", "tmux", "herdr", "imv", "fcitx5", "autostart",
    "gtk-3.0", "gtk-4.0", "fontconfig", "fastfetch", "hyprland-preview-share-picker",
    "chromium-flags.conf", "mimeapps.list", "user-dirs.dirs", "user-dirs.locale",
    "kdeglobals", "dolphinrc",
)
HOME_FILES = tuple(".config/" + name for name in CONFIGS) + (
    ".XCompose", ".local/state/omarchy/current", ".local/state/omarchy/toggles",
    ".local/share/nautilus-python/extensions", ".local/bin/google-chrome-stable",
    ".local/bin/xdg-terminal-exec",
    ".local/share/applications/google-chrome.desktop",
    ".local/share/applications/omarchy-arch.desktop",
    ".local/share/applications/Tailscale.desktop",
)
HARDWARE_FILES = (
    ".local/bin/fix-audio-output",
    ".config/systemd/user/fix-audio-output.service",
    ".config/systemd/user/sof-hda-alsa-init.service",
    ".config/systemd/user/stay-awake.service",
    ".config/systemd/user/pipewire.service.d/10-sof-hda-alsa-init.conf",
    ".config/systemd/user/pipewire-pulse.service.d/10-sof-hda-alsa-init.conf",
)
SYSTEM_FILES = (
    "/usr/local/bin/fix-audio-output-global",
    "/etc/systemd/user/fix-audio-output-global.service",
    "/etc/sddm.conf.d", "/etc/profile.d/omarchy-debian.sh",
    "/etc/pam.d/omarchy-lock-password", "/etc/fastfetch/config.jsonc",
    "/etc/systemd/oomd.conf.d/10-omarchy.conf",
    "/etc/systemd/system.conf.d/20-omarchy-nofile.conf",
    "/etc/systemd/user.conf.d/20-omarchy-nofile.conf",
    "/etc/systemd/zram-generator.conf.d/90-omarchy.conf",
    "/etc/systemd/logind.conf.d", "/etc/systemd/sleep.conf.d",
    "/etc/initramfs-tools/conf.d/resume", "/etc/initramfs-tools/conf.d/omarchy-resume",
    "/usr/lib/systemd/system-sleep/unmount-fuse",
    "/usr/share/uwsm/env.d/10-omarchy", "/usr/lib/environment.d/10-omarchy-fcitx.conf",
    "/usr/share/fontconfig/conf.avail/50-omarchy.conf", "/etc/fonts/conf.d/50-omarchy.conf",
    "/usr/lib/systemd/oomd.conf.d/10-omarchy.conf",
    "/usr/lib/systemd/system.conf.d/20-omarchy-nofile.conf",
    "/usr/lib/systemd/user.conf.d/20-omarchy-nofile.conf",
    "/etc/systemd/zram-generator.conf.d/90-omarchy.conf",
    "/etc/modprobe.d/nvidia.conf",
)
EXCLUDED = {".git", "__pycache__", "bookmarks", "btop.log", "cached_layouts"}


def excluded(path):
    return (path.name in EXCLUDED or ".bak" in path.name
            or path.suffix in {".pyc", ".log"} or path.name.endswith(".sample"))


def files(path):
    if excluded(path):
        return
    if path.is_symlink() or path.is_file():
        yield path
    elif path.is_dir():
        for child in sorted(path.iterdir()):
            yield from files(child)


def fingerprint(path):
    if path.is_symlink():
        return hashlib.sha256(os.readlink(path).encode()).hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args[0]}: {result.stderr.strip()}")
    return result.stdout


def capture(home):
    # Stage the complete export before replacing a previous capture.
    with tempfile.TemporaryDirectory(prefix=".capture-", dir=ROOT) as temporary:
        stage = Path(temporary)
        entries = []
        for group, base, names in (("home", home, HOME_FILES),
                                   ("hardware", home, HARDWARE_FILES),
                                   ("system", Path("/"), SYSTEM_FILES)):
            for name in names:
                source = base / name.lstrip("/")
                for item in files(source):
                    relative = item.relative_to(base)
                    dest = stage / group / relative
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    if item.is_symlink():
                        dest.symlink_to(os.readlink(item))
                    else:
                        shutil.copy2(item, dest)
                        if relative.as_posix() == ".config/dolphinrc":
                            content = dest.read_text()
                            dest.write_text("\n".join(line for line in content.splitlines()
                                                      if not line.startswith("DirHistory")) + "\n")
                    entries.append({"path": dest.relative_to(stage).as_posix(),
                                    "source": str(item), "sha256": fingerprint(dest),
                                    "mode": oct(item.lstat().st_mode & 0o777),
                                    "symlink": os.readlink(item) if item.is_symlink() else None})
        upstream = home / ".local/share/omarchy-debian/upstream"
        if (upstream / ".git").is_dir():
            (stage / "upstream").mkdir()
            patch = subprocess.run(["git", "-C", str(upstream), "diff", "--binary", "HEAD"],
                                   capture_output=True, check=True).stdout
            (stage / "upstream/installed-overlay.patch").write_bytes(patch)
            # Preserve Debian-only files that git diff does not include.
            for name in command("git", "-C", str(upstream), "ls-files", "--others",
                                "--exclude-standard", "-z").split("\0"):
                if not name:
                    continue
                dest = stage / "upstream/extra" / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(upstream / name, dest)
        manifest = {"captured_at": datetime.now(timezone.utc).isoformat(),
                    "source_home": str(home), "entries": entries,
                    "upstream_commit": command("git", "-C", str(upstream), "rev-parse", "HEAD").strip()
                    if (upstream / ".git").is_dir() else None}
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        old = ROOT / ".customizations-previous"
        if old.exists():
            raise RuntimeError(f"Previous capture recovery folder exists: {old}")
        if PROFILE.exists():
            PROFILE.rename(old)
        try:
            shutil.copytree(stage, PROFILE, symlinks=True)
        except BaseException:
            if PROFILE.exists():
                shutil.rmtree(PROFILE)
            if old.exists():
                old.rename(PROFILE)
            raise
        if old.exists():
            shutil.rmtree(old)
    print(f"Captured {len(entries)} desktop, hardware, and system files in {PROFILE}")


def validate():
    manifest = json.loads((PROFILE / "manifest.json").read_text())
    for entry in manifest["entries"]:
        path = PROFILE / entry["path"]
        if fingerprint(path) != entry["sha256"]:
            raise RuntimeError(f"Capture differs from manifest: {entry['path']}")
    print(f"Verified {len(manifest['entries'])} captured files.")
    return manifest


def restore(home, apply, hardware):
    manifest = validate()
    old_home = manifest["source_home"]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    backup = home / ".local/state/omarchy-debian/restore-backups" / stamp
    for entry in manifest["entries"]:
        group, relative = entry["path"].split("/", 1)
        if group == "system" or (group == "hardware" and not hardware):
            continue
        # Every target must stay in the selected home, including parent symlinks.
        target = home / relative
        if not target.parent.resolve().is_relative_to(home.resolve()):
            raise RuntimeError(f"Destination parent escapes home: {target}")
        source = PROFILE / entry["path"]
        print(f"{'Restore' if apply else 'Would restore'} {target}")
        if not apply:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() or target.is_symlink():
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), saved)
        if source.is_symlink():
            target.symlink_to(os.readlink(source).replace(old_home + "/", str(home) + "/"))
        else:
            content = source.read_bytes()
            try:
                content = content.decode().replace(old_home + "/", str(home) + "/").encode()
            except UnicodeDecodeError:
                pass
            target.write_bytes(content)
            target.chmod(int(entry["mode"], 8))
    if apply:
        print(f"Existing files backed up under {backup}")
        print("Log out and back in to load the restored desktop. Units are not enabled automatically.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "check", "restore"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--apply", action="store_true", help="write restored files (default is preview)")
    parser.add_argument("--hardware", action="store_true", help="also restore user audio/power scripts and units")
    args = parser.parse_args()
    home = args.home.expanduser().resolve()
    if args.action == "capture":
        capture(home)
    elif args.action == "check":
        validate()
    else:
        restore(home, args.apply, args.hardware)


if __name__ == "__main__":
    main()
