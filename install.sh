#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
snapshot_mount=''
skip_source_builds=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--snapshot-mount PATH] [--skip-source-builds]

Install the pinned Omarchy desktop on Debian 13, then activate the Arch/AUR
package bridge and Debian system adapters. Run as a regular desktop user.

--snapshot-mount PATH  Existing separate mounted filesystem for Timeshift.
                       Without one, Timeshift is installed but no snapshot is
                       created until you configure a destination later.
--skip-source-builds   Skip optional Omarchy companion-app source builds.
EOF
}

while (($#)); do
  case $1 in
    --snapshot-mount)
      (($# >= 2)) || { usage >&2; exit 2; }
      snapshot_mount=$2; shift 2 ;;
    --skip-source-builds) skip_source_builds=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ $EUID -ne 0 ]] || { echo 'Run as the desktop user, not root.' >&2; exit 2; }
[[ -r /etc/os-release ]] || { echo 'Cannot identify this operating system.' >&2; exit 2; }
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_CODENAME:-} == trixie ]] || {
  echo 'This installer targets Debian 13 Trixie.' >&2; exit 2;
}

if [[ -n $snapshot_mount ]]; then
  [[ $snapshot_mount == /* && -d $snapshot_mount ]] || {
    echo 'Snapshot mount must be an existing absolute directory.' >&2; exit 2;
  }
  root_source=$(findmnt -no SOURCE /)
  target_source=$(findmnt -M -no SOURCE "$snapshot_mount" 2>/dev/null || true)
  [[ -n $target_source && $target_source != "$root_source" ]] || {
    echo 'Snapshot mount must be a separate mounted filesystem.' >&2; exit 2;
  }
fi

installer_args=()
(( skip_source_builds )) && installer_args+=(--skip-source-builds)
"$root/install-omarchy-debian.sh" "${installer_args[@]}"
"$root/bridge/activate.sh"
system_args=()
[[ -n $snapshot_mount ]] && system_args=(--snapshot-mount "$snapshot_mount")
"$root/bridge/activate-system.sh" "${system_args[@]}"

echo
echo 'Omarchy on Debian installation finished.'
echo 'Log out, select the Omarchy on Debian session, and log in again.'
echo 'Keep this folder in place: ~/.local/bin commands link to its bridge scripts.'
