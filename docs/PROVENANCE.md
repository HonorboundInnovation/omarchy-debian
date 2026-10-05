# Source reconciliation — October 4, 2026

The development checkout is `/mnt/storage/Projects/Omarchy - Debian`.
The original installer and README are preserved in the first Git commit.

| Original location | Decision |
| --- | --- |
| `~/Omarchy_on_Debian/Omarchy_on_Debian/` | Comprehensive installer, runtime patch, theme assets, supplemental installer, historical package report |
| `~/omarchy-on-debian-install/` | Complete-install wrapper and portable bridge, including configurable snapshot destinations and guarded update snapshots |
| `~/omarchy-debian-bridge/` | Compared every file; portable versions supersede the old snapshot/update/activation/test differences. Historical STATUS.md retained |
| `~/.codex/skills/` | Current Debian Omarchy and crash skills |
| `~/.config/` and selected local scripts | Live desktop profile, including SCU menu and current bindings |
| `~/.local/share/omarchy-debian/upstream/` | Installed tracked overlay and untracked Debian additions |

The comprehensive installer provides stronger dependency fallback handling,
actual runtime fixes, and theme preferences. The smaller bundle's Waybar startup
suppression was carried over. The old Python skill adapter incorrectly stated
that Arch/AUR were unavailable; it now deploys the current bundled skills rather
than making brittle replacements in upstream instructions.

Corrections during consolidation: command substitutions no longer hide failures
inside declarations, snapshot arguments are checked before destination probes,
UUID lookup uses the exact mountpoint, and snapshot setup instructions point to
the bridge activation script. ShellCheck warnings were corrected.

The Debian query shim is now maintained in `adapters/pacman` instead of embedded
in the installer. It ignores residual/uninstalled dpkg records and fails missing
package-info queries. The bridge checks every package in mixed Debian/Arch
queries, preserving failure when any requested package is absent. Tests exercise
the consolidated adapter rather than relying on this machine's old installed copy.

Old source folders and running desktop files remain in place. Collection did not
run the desktop installer, switch live bridge symlinks, restart the shell, alter
the bootloader, or restore a snapshot. Develop the installer here; refresh the
profile with `python3 scripts/customizations.py capture` after desktop edits.
