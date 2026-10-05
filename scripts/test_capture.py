#!/usr/bin/env python3
"""Test export rejection and portability without reading the live desktop."""

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import customizations as profile


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "private-user"
        self.home.mkdir()
        self.export = self.root / "customizations"
        self.system_files = profile.SYSTEM_FILES
        for name, value in (("ROOT", self.root), ("PROFILE", self.export), ("SYSTEM_FILES", ())):
            override = patch.object(profile, name, value)
            override.start()
            self.addCleanup(override.stop)

    def write(self, name, content):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def capture(self):
        with contextlib.redirect_stdout(io.StringIO()):
            profile.capture(self.home)

    def snapshot(self):
        return {path.relative_to(self.export).as_posix(): profile.fingerprint(path)
                for path in profile.files(self.export)}

    def test_portable_capture_and_history_removal(self):
        self.write(".config/hypr/bindings.lua", f'launch = "{self.home}/bin/app"\n')
        self.write(".config/dolphinrc", "DirHistory1=/private/projects\nShowHiddenFiles=true\n")
        self.write(".config/kdeglobals", "History Items[$e]=file:///media/private/disk\nColorScheme=dark\n")
        self.write(".config/btop/btop.conf", '# Example: /home/user\n')
        link = self.home / ".local/state/omarchy/current/background"
        link.parent.mkdir(parents=True)
        link.symlink_to(self.home / ".config/hypr/bindings.lua")
        self.capture()
        manifest = json.loads((self.export / "manifest.json").read_text())
        self.assertEqual(manifest["format_version"], 2)
        self.assertNotIn("source_home", manifest)
        self.assertTrue(all(entry["source"].startswith("home:") for entry in manifest["entries"]))
        bindings = self.export / "home/.config/hypr/bindings.lua"
        self.assertIn("@HOME@/bin/app", bindings.read_text())
        exported_link = self.export / "home/.local/state/omarchy/current/background"
        self.assertFalse(os.path.isabs(os.readlink(exported_link)))
        self.assertEqual(exported_link.resolve(), bindings)
        self.assertNotIn("History", (self.export / "home/.config/dolphinrc").read_text())
        self.assertNotIn("History", (self.export / "home/.config/kdeglobals").read_text())
        with contextlib.redirect_stdout(io.StringIO()):
            profile.validate()

    def test_scanner_rejects_values_and_preserves_previous_capture(self):
        config = self.write(".config/hypr/settings.conf", "enabled=true\n")
        self.capture()
        previous = self.snapshot()
        unsafe = (
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "ghp_" + "a" * 36,
            "github_pat_" + "a" * 50,
            "sk-proj-" + "a" * 40,
            "AKIA" + "A" * 16,
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.abcdefghijk",
            'password = "short"',
            '"client_secret": "sensitive-value"',
            "ACCESS_TOKEN=sensitive-value",
            "refresh-token: sensitive-value",
            "AWS_SECRET_ACCESS_KEY=sensitive-value",
            'token="${TOKEN:-sensitive-value}"',
            "Authorization: Bearer abcdefghijklmnop",
            "Authorization: Basic dXNlcjpwYXNzd29yZA==",
            "Cookie: sessionid=sensitive-value",
            "session_cookie=sensitive-value",
            "https://user:password@example.invalid/path",
            "https://user%3Apassword%40example.invalid/path",
            "RESUME=UUID=01234567-89ab-cdef-0123-456789abcdef",
            '"resume_uuid": "01234567-89ab-cdef-0123-456789abcdef"',
            "/dev/disk/by-uuid/ABCD-1234",
            "/home/another-user/private",
            r"\/home\/another-user\/private",
            r"\u002fhome\u002fanother-user\u002fprivate",
            "pci-1234_56_1a.3-platform-audio",
            r"pci-1234_56_1a\.3",
        )
        for content in unsafe:
            with self.subTest(content=content):
                config.write_text(content)
                with self.assertRaisesRegex(RuntimeError, "Export rejected") as caught:
                    self.capture()
                self.assertNotIn(content, str(caught.exception), "Error exposed matched content")
                self.assertEqual(self.snapshot(), previous)
                self.assertFalse((self.root / ".customizations-previous").exists())
                self.assertEqual(list(self.root.glob(".capture-*")), [])

    def test_scan_covers_names_links_binary_and_utf16(self):
        stage = self.root / "stage"
        stage.mkdir()
        cases = (
            (".env.production", b"ordinary data"),
            ("cookies.txt", b"ordinary data"),
            ("binary.png", b"\x89PNG\0password=private-value\xff"),
            ("utf16.conf", 'api_key="private-value"'.encode("utf-16")),
        )
        for name, content in cases:
            with self.subTest(name=name):
                path = stage / name
                path.write_bytes(content)
                with self.assertRaisesRegex(RuntimeError, "Export rejected"):
                    profile.scan_export(stage)
                path.unlink()
        link = stage / "broken-link"
        link.symlink_to("/home/private-user/missing")
        with self.assertRaisesRegex(RuntimeError, "absolute user path"):
            profile.scan_export(stage)
        link.unlink()
        # Non-filesystem UUIDs, code identifiers and variable references are safe.
        (stage / "safe.conf").write_text(
            "urn:c2pa:01234567-89ab-cdef-0123-456789abcdef\n"
            'function searchableToken(value) {}\npassword="$PASSWORD"\n'
            'api_key=${API_KEY}\nhide_token_restore: true\nUUID=$uuid\n')
        profile.scan_export(stage)

    def test_upstream_patch_and_untracked_files_are_scanned(self):
        self.write(".config/hypr/settings.conf", "enabled=true\n")
        self.capture()
        previous = self.snapshot()
        upstream = self.home / ".local/share/omarchy-debian/upstream"
        upstream.mkdir(parents=True)

        def git(*args):
            subprocess.run(["git", "-C", str(upstream), *args], check=True,
                           capture_output=True)

        git("init", "--quiet")
        tracked = upstream / "settings.conf"
        tracked.write_text("enabled=true\n")
        git("add", "settings.conf")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Fixture")
        tracked.write_text('password="private-value"\n')
        with self.assertRaisesRegex(RuntimeError, "installed-overlay.patch"):
            self.capture()
        self.assertEqual(self.snapshot(), previous)
        git("checkout", "--", "settings.conf")
        tracked.write_text(f'path="{self.home}/bin/private-app"\n')
        with self.assertRaisesRegex(RuntimeError, "installed-overlay.patch"):
            self.capture()
        self.assertEqual(self.snapshot(), previous)
        git("checkout", "--", "settings.conf")
        extra = upstream / "extra.conf"
        extra.write_text('api_key="private-value"\n')
        with self.assertRaisesRegex(RuntimeError, "upstream/extra/extra.conf"):
            self.capture()
        self.assertEqual(self.snapshot(), previous)
        extra.write_text("enabled=true\n")
        self.capture()
        # check also scans files not covered by the home/system checksum list.
        (self.export / "upstream/extra/extra.conf").write_text('api_key="private-value"\n')
        with self.assertRaisesRegex(RuntimeError, "Export rejected"):
            profile.validate()

    def test_host_identifiers_are_not_allowlisted(self):
        self.assertNotIn(".local/bin/fix-audio-output", profile.HARDWARE_FILES)
        self.assertNotIn("/etc/initramfs-tools/conf.d/resume", self.system_files)
        self.assertNotIn("/etc/initramfs-tools/conf.d/omarchy-resume", self.system_files)
        self.assertNotIn("/usr/local/bin/fix-audio-output-global", self.system_files)


if __name__ == "__main__":
    unittest.main()
