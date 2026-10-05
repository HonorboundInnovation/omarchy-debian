# Validation — October 4, 2026

Executed `SHELLCHECK=/tmp/omarchy-repo-tools/usr/bin/shellcheck ./scripts/check.sh`.
ShellCheck 0.10.0 was extracted into a temporary directory from Debian's package;
the check did not install packages or change the desktop.

Passed:

- Shell syntax, Python syntax, Lua syntax, and JSON parsing.
- Installer heredoc checks, including generated scripts and inline Python.
- ShellCheck at warning severity.
- Runtime patch applies to the pinned source; the three patched files match the
  currently installed Debian fixes.
- Bridge install/update/export/query routing using command mocks.
- Mixed Debian/Arch package queries; missing packages and residual dpkg records
  fail correctly; host package mutations are refused.
- Snapshot argument and destination/configuration guards.
- Capture checksums for 171 files and Git staging completeness.
- Restore preview, backups, home relocation, active theme symlink, optional
  hardware files, and escaping-parent protection in temporary directories.
- Credential-pattern check: no matches in the consolidated files.
- Comparison of deployed Omarchy bin/config/default/shell/themes/migrations
  against the upstream working checkout: no additional live changes were missed.

The checks do not replace a complete installation on a fresh Debian 13 machine.
Optional source builds, graphical Arch exports, hardware-specific audio recovery,
boot/greeter behavior on another machine, and Timeshift restore are not verified
by these tests. The running system was not reinstalled or migrated during this
collection.
