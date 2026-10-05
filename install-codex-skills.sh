#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  echo 'Usage: ./install-codex-skills.sh'
  echo 'Copy the bundled Omarchy and crash-diagnosis skills into your Codex skills directory.'
  exit 0
fi
(( $# == 0 )) || { echo 'Usage: ./install-codex-skills.sh' >&2; exit 2; }

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_dir=${CODEX_HOME:-$HOME/.codex}/skills
mkdir -p -- "$target_dir"
for name in omarchy diagnose-crash; do
  target=$target_dir/$name
  if [[ -e $target || -L $target ]]; then
    echo "Keeping existing Codex skill: $target"
    continue
  fi
  cp -a -- "$root/skills/$name" "$target"
  echo "Installed Codex skill: $target"
done
