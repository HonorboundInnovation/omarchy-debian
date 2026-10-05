#!/usr/bin/env python3
"""Exercise restoration in a temporary home, without changing this desktop."""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/customizations.py"


def run(home, *args, success=True):
    result = subprocess.run(["python3", str(SCRIPT), "restore", "--home", str(home), *args],
                            capture_output=True, text=True)
    if success and result.returncode:
        raise AssertionError(result.stderr)
    if not success and result.returncode == 0:
        raise AssertionError("Restore accepted a destination that escapes home")
    return result


def main():
    with tempfile.TemporaryDirectory() as temp:
        home = Path(temp) / "home"
        home.mkdir()
        run(home)
        assert list(home.iterdir()) == [], "Preview changed the destination"
        bindings = home / ".config/hypr/bindings.lua"
        bindings.parent.mkdir(parents=True)
        bindings.write_text("existing bindings\n")
        run(home, "--apply")
        assert "existing bindings" not in bindings.read_text()
        assert "@HOME@" not in bindings.read_text()
        assert str(home) + "/.npm-global/bin/codex" in bindings.read_text()
        launcher = home / ".local/share/applications/google-chrome.desktop"
        assert str(home) + "/.local/bin/google-chrome-stable" in launcher.read_text()
        assert "@HOME@" not in launcher.read_text()
        backups = list((home / ".local/state/omarchy-debian/restore-backups").rglob("bindings.lua"))
        assert len(backups) == 1 and backups[0].read_text() == "existing bindings\n"
        background = home / ".local/state/omarchy/current/background"
        assert background.is_symlink() and background.exists(), "Active theme link broke"
        assert not os.path.isabs(os.readlink(background))
        assert background.resolve().is_relative_to(home)
        assert not (home / ".config/systemd/user/stay-awake.service").exists()
        assert not (home / "etc").exists(), "Root reference files were restored into home"
        run(home, "--apply", "--hardware")
        assert (home / ".config/systemd/user/stay-awake.service").is_file()
        assert not (home / ".local/bin/fix-audio-output").exists()
        assert not (home / ".config/systemd/user/default.target.wants").exists()
        escape = Path(temp) / "escape-home"
        outside = Path(temp) / "outside"
        escape.mkdir()
        outside.mkdir()
        (escape / ".config").symlink_to(outside, target_is_directory=True)
        run(escape, "--apply", success=False)
        assert list(outside.iterdir()) == [], "Restore followed an escaping parent symlink"
    print("Restore tests passed: preview, backups, relocation, symlinks, hardware selection, path guards.")


if __name__ == "__main__":
    main()
