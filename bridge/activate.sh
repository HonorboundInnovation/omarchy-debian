#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -ne 0 ]] || { echo 'Run as your desktop user.' >&2; exit 2; }

# Debian keeps ownership of the host. These are the only host dependencies.
sudo apt-get install -- distrobox podman
"$root/bin/omarchy-arch" setup

mkdir -p "$HOME/.local/bin"
for source in "$root"/bin/*; do
  name=${source##*/}
  target="$HOME/.local/bin/$name"
  if [[ -e $target && ! -L $target ]]; then
    echo "Refusing to replace existing $target" >&2
    exit 1
  fi
done
for source in "$root"/bin/*; do
  name=${source##*/}
  target="$HOME/.local/bin/$name"
  ln -sfn -- "$source" "$target"
done
echo 'Omarchy Debian package bridge activated. Open a new terminal to refresh PATH.'
