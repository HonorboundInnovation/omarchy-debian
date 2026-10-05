#!/usr/bin/env python3
"""Capture and restore the desktop profile without copying account credentials."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from urllib.parse import unquote

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
    ".config/systemd/user/sof-hda-alsa-init.service",
    ".config/systemd/user/stay-awake.service",
    ".config/systemd/user/pipewire.service.d/10-sof-hda-alsa-init.conf",
    ".config/systemd/user/pipewire-pulse.service.d/10-sof-hda-alsa-init.conf",
)
SYSTEM_FILES = (
    "/etc/sddm.conf.d", "/etc/profile.d/omarchy-debian.sh",
    "/etc/pam.d/omarchy-lock-password", "/etc/fastfetch/config.jsonc",
    "/etc/systemd/oomd.conf.d/10-omarchy.conf",
    "/etc/systemd/system.conf.d/20-omarchy-nofile.conf",
    "/etc/systemd/user.conf.d/20-omarchy-nofile.conf",
    "/etc/systemd/zram-generator.conf.d/90-omarchy.conf",
    "/etc/systemd/logind.conf.d", "/etc/systemd/sleep.conf.d",
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
HOME_PLACEHOLDER = "@HOME@"

# These are detection rules, not a guarantee that arbitrary secrets can be found.
# Match concrete values rather than words such as searchableToken or UUID=$uuid.
SCAN_RULES = (
    ("private key", re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")),
    ("API/access key", re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
        r"sk-(?:proj-|svcacct-|ant-)?[A-Za-z0-9_-]{20,}|"
        r"(?:AKIA|ASIA)[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")),
    ("credential URL", re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s/\"'<>:@]+:[^\s/\"'<>@]+@", re.I)),
    ("authorization credential", re.compile(
        r"\b(?:Bearer|Basic)\s+[A-Za-z0-9_+/=-]{8,}", re.I)),
    ("authentication cookie", re.compile(
        r"(?:\b(?:Set-Cookie|Cookie)[\"']?\s*[:=]\s*[\"']?[^\s\"']+=|"
        r"\b(?:sessionid|session_id|auth_cookie|session_cookie)[\"']?\s*[:=]\s*[\"']?[A-Za-z0-9_-]{8,}|"
        r"# Netscape HTTP Cookie File)", re.I)),
    ("filesystem UUID", re.compile(
        r"(?:\b(?:[a-z]+[_-])*(?:PART)?UUID[\"']?\s*[:=]\s*[\"']?|/dev/disk/by-(?:part)?uuid/|"
        r"/(?:run/)?media/[^/\s]+/)"
        r"[0-9a-f]{4,}(?:-[0-9a-f]+)*\b", re.I)),
    ("absolute user path", re.compile(r"/(?:home|Users|(?:run/)?media)/[A-Za-z0-9_.-]+(?:/|\b)|/root/")),
    ("audio PCI topology", re.compile(r"\bpci-[0-9a-f]{4}[_:][0-9a-f]{2}[_:][0-9a-f]{2}\\?\.[0-7]", re.I)),
)
SECRET_ASSIGNMENT = re.compile(
    r"(?<![\w-])(?:[A-Z0-9]+[_-])*(?:password|passwd|pwd|api[_-]?key|"
    r"client[_-]?secret|access[_-]?token|refresh[_-]?token|auth[_-]?token|"
    r"secret[_-]?(?:access[_-]?)?key|private[_-]?key|"
    r"token|secret|authorization|cookie)[\"']?\s*[:=]\s*"
    r"(?:\"([^\"\r\n]*)\"|'([^'\r\n]*)'|(\$\{[^}\r\n]*\}|[^\s,;#}\r\n]+))", re.I)


def scan_export(tree, home=None):
    """Check all exported bytes, names and link targets without following links."""
    findings = []
    for path in sorted(tree.rglob("*")):
        relative = path.relative_to(tree).as_posix()
        if (path.name == ".env" or path.name.startswith(".env.")
                or path.name.lower() in {"cookies", "cookies.txt", "cookies.sqlite",
                                         "cookies.json", ".netrc", "credentials.json"}):
            findings.append((relative, "credential file"))
        texts = [relative]
        if path.is_symlink():
            texts.append(os.readlink(path))
        elif path.is_file():
            data = path.read_bytes()
            # Include strings embedded in binary files and UTF-16 configurations.
            texts.append(data.decode("utf-8", errors="replace"))
            if b"\0" in data:
                texts.extend(data.decode(encoding, errors="replace")
                             for encoding in ("utf-16-le", "utf-16-be"))
        for content in texts:
            content = re.sub(r"\\u([0-9a-fA-F]{4})", lambda match: chr(int(match[1], 16)), content)
            content = unquote(content.replace(r"\/", "/").replace(r'\"', '"').replace(r"\'", "'"))
            for label, pattern in SCAN_RULES:
                if pattern.search(content):
                    findings.append((relative, label))
            if home and re.search(re.escape(str(home)) + r"(?=/|\b)", content):
                findings.append((relative, "source home path"))
            for match in SECRET_ASSIGNMENT.finditer(content):
                value = next(value for value in match.groups() if value is not None)
                if (value and value.lower() not in {"true", "false", "none", "null"}
                        and not re.fullmatch(r"\$(?:[A-Za-z_][A-Za-z0-9_]*|[0-9@*]|\{[A-Za-z_][A-Za-z0-9_]*\})", value)):
                    findings.append((relative, "credential assignment"))
    if findings:
        # Never print matched values; an error log must not become a secret dump.
        details = "\n".join(f"  {path}: {label}" for path, label in sorted(set(findings)))
        raise RuntimeError(f"Export rejected by secret/privacy scan:\n{details}")


def portable_text(content, home):
    return re.sub(re.escape(str(home)) + r"(?=/|$|[\s\"'])", HOME_PLACEHOLDER, content)


def export_file(source, dest, home, relative=None, portable=True):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        link = os.readlink(source)
        if relative is not None and link.startswith(str(home) + "/"):
            link = os.path.relpath(link, home / relative.parent)
        dest.symlink_to(link)
        return
    shutil.copy2(source, dest)
    try:
        content = dest.read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        return
    if portable:
        content = portable_text(content, home)
    if relative is not None and relative.as_posix() == ".config/dolphinrc":
        content = "\n".join(line for line in content.splitlines()
                            if not line.startswith("DirHistory")) + "\n"
    if relative is not None and relative.as_posix() == ".config/kdeglobals":
        content = "\n".join(line for line in content.splitlines()
                            if not line.startswith(("History Items", "Recent URLs"))) + "\n"
    # This stock comment illustrates a generic path, not a captured user path.
    if relative is not None and relative.as_posix() == ".config/btop/btop.conf":
        content = content.replace("/home/user", "$HOME")
    dest.write_bytes(content.encode("utf-8"))


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
                    export_file(item, dest, home, relative if group != "system" else None)
                    entries.append({"path": dest.relative_to(stage).as_posix(),
                                    "source": f"{'system' if group == 'system' else 'home'}:{relative.as_posix()}",
                                    "sha256": fingerprint(dest),
                                    "mode": oct(item.lstat().st_mode & 0o777),
                                    "symlink": os.readlink(dest) if dest.is_symlink() else None})
        upstream = home / ".local/share/omarchy-debian/upstream"
        if (upstream / ".git").is_dir():
            (stage / "upstream").mkdir()
            patch = subprocess.run(["git", "-C", str(upstream), "diff", "--binary", "HEAD"],
                                   capture_output=True, check=True).stdout
            # Recovery patches must retain their exact bytes and hunk hashes.
            (stage / "upstream/installed-overlay.patch").write_bytes(patch)
            # Preserve Debian-only files that git diff does not include.
            for name in command("git", "-C", str(upstream), "ls-files", "--others",
                                "--exclude-standard", "-z").split("\0"):
                if not name:
                    continue
                dest = stage / "upstream/extra" / name
                export_file(upstream / name, dest, home, portable=False)
        manifest = {"format_version": 2,
                    "captured_at": datetime.now(timezone.utc).isoformat(), "entries": entries,
                    "upstream_commit": command("git", "-C", str(upstream), "rev-parse", "HEAD").strip()
                    if (upstream / ".git").is_dir() else None}
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        scan_export(stage, home)
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
    if manifest.get("format_version") != 2:
        raise RuntimeError("Unsupported capture format; recapture using the current script")
    for entry in manifest["entries"]:
        path = PROFILE / entry["path"]
        if fingerprint(path) != entry["sha256"]:
            raise RuntimeError(f"Capture differs from manifest: {entry['path']}")
    scan_export(PROFILE, Path.home())
    print(f"Verified {len(manifest['entries'])} captured files.")
    return manifest


def restore(home, apply, hardware):
    manifest = validate()
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
            target.symlink_to(os.readlink(source))
        else:
            content = source.read_bytes()
            try:
                content = content.decode().replace(HOME_PLACEHOLDER, str(home)).encode()
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
