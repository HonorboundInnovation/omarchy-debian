#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -ne 0 ]] || { echo 'Run as your desktop user.' >&2; exit 2; }
snapshot_mount=''
case $# in
  0) ;;
  2) [[ $1 == --snapshot-mount ]] || { echo 'Usage: activate-system.sh [--snapshot-mount PATH]' >&2; exit 2; }
     snapshot_mount=$2 ;;
  *) echo 'Usage: activate-system.sh [--snapshot-mount PATH]' >&2; exit 2 ;;
esac
if [[ -n $snapshot_mount ]]; then
  [[ $snapshot_mount == /* && -d $snapshot_mount ]] || { echo 'Snapshot mount must be an existing absolute directory.' >&2; exit 2; }
  root_source=$(findmnt -no SOURCE /)
  target_source=$(findmnt -M -no SOURCE "$snapshot_mount" 2>/dev/null || true)
  [[ -n $target_source && $target_source != "$root_source" ]] || {
    echo 'Snapshot mount must be a separate mounted filesystem.' >&2; exit 2;
  }
  [[ -n $(findmnt -M -no UUID "$snapshot_mount" 2>/dev/null) ]] || {
    echo 'Snapshot mount has no filesystem UUID.' >&2; exit 2;
  }
fi
sudo apt-get install -- timeshift

for name in omarchy-snapshot omarchy-hibernation-available omarchy-hibernation-setup \
  omarchy-hibernation-remove omarchy-refresh-limine omarchy-refresh-plymouth \
  omarchy-plymouth-set omarchy-update-keyring \
  omarchy-update-restart omarchy-update-pkg-prune omarchy-update-orphan-pkgs; do
  target="$HOME/.local/bin/$name"
  if [[ -e $target && ! -L $target ]]; then
    echo "Refusing to replace existing $target" >&2
    exit 1
  fi
done
for name in omarchy-snapshot omarchy-hibernation-available omarchy-hibernation-setup \
  omarchy-hibernation-remove omarchy-refresh-limine omarchy-refresh-plymouth \
  omarchy-plymouth-set omarchy-update-keyring \
  omarchy-update-restart omarchy-update-pkg-prune omarchy-update-orphan-pkgs; do
  ln -sfn -- "$root/bin/$name" "$HOME/.local/bin/$name"
done

if [[ -n $snapshot_mount ]]; then
  config=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-debian/snapshot-mount
  mkdir -p -- "${config%/*}"
  printf '%s\n' "$snapshot_mount" > "$config.tmp"
  mv -f -- "$config.tmp" "$config"
  "$root/bin/omarchy-snapshot" create
  echo 'Debian system adapters activated; initial Timeshift snapshot created.'
else
  echo 'Debian system adapters activated. Set a snapshot mount later with activate-system.sh --snapshot-mount PATH.'
fi
