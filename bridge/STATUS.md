# Omarchy on Debian: current state

## Working now

- Debian 13 remains the host package owner through APT.
- A rootless Arch Distrobox has real pacman and yay (verified in the user's
  desktop terminal on 2026-09-24).
- `omarchy pkg install` offers Debian, Arch, and AUR sources. `omarchy pkg
  remove` and `omarchy pkg drop` route package removals to the owning system.
- `omarchy update` runs APT, pacman, and AUR updates in sequence.
- The desktop package guards include only exported Arch apps, avoiding false
  host-installed results from Arch's internal libraries and services.
- Package-query and dispatch tests pass. The combined menu package query runs
  in roughly 0.06 seconds on this machine.
- Debian-native boot/hibernation, keyring, package cleanup, and Plymouth
  refresh commands have been added. Timeshift is installed on the host.
- Stable, RC, and edge source channels can be selected. Source revisions can
  be staged and checked against the Debian patch without altering the system.
- The first real Timeshift RSYNC snapshot succeeded on `/mnt/storage` in 104
  seconds (2026-09-24_22-48-28, 738793 files).
- A live stable-channel source check fetched v4.0.4 and matched the installed
  source commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`.

## Still to verify or port

- No new graphical app was installed at the user's request. Desktop export is
  covered by command tests; runtime export of a real app is unverified.
- Timeshift restore has not been tested; it changes live system state.
- The Debian adapter is pinned to Omarchy 4.0.4. Source staging is a review
  step, not a release installer. New upstream versions can change dependencies,
  migrations, shell components, and Arch-specific scripts. A maintained Debian
  release deployment mechanism is still needed.
- Fingerprint setup was not ported because this machine has no fingerprint
  reader. Factory reset remains disabled by the original Debian installer.

The Arch container is deliberately an app environment, not a second owner of
Debian's `/usr`, kernel, bootloader, or system services.
