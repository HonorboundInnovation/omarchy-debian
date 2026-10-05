#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for script in "$root"/bin/* "$root"/activate*.sh; do bash -n "$script"; done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/podman" <<'EOF'
#!/usr/bin/env bash
[[ $1 == container && $2 == exists ]]
EOF
cat >"$tmp/bin/distrobox" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_LOG"
if [[ $1 == enter && " $* " == *' /usr/bin/pacman -Qlq '* ]]; then
  printf '/usr/share/applications/example.desktop\n/usr/bin/example\n'
fi
if [[ $1 == enter && " $* " == *' /usr/bin/pacman -Qq '* ]]; then printf 'example\n'; fi
if [[ $1 == enter && " $* " == *' /usr/bin/pacman -Qi '* ]]; then printf 'Name : example\nProvides : None\n\n'; fi
if [[ $1 == enter && " $* " == *' /usr/bin/pacman -Q '* ]]; then printf 'example 1.0\n'; fi
EOF
cat >"$tmp/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$tmp/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$tmp/bin/apt" <<'EOF'
#!/usr/bin/env bash
printf 'Listing...\nexample/old 2.0 amd64 [upgradable from: 1.0]\n'
EOF
cat >"$tmp/bin/omarchy-restart-shell" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy-restart-shell\n' >>"$TEST_LOG"
EOF
cat >"$tmp/bin/timeshift" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  '-no SOURCE /') echo /dev/test-root ;;
  *'-no SOURCE '*) echo /dev/test-snapshot ;;
  *'-no UUID '*) echo test-snapshot-uuid ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin"/*
mkdir -p "$tmp/snapshot"
export PATH="$tmp/bin:$root/bin:$PATH" TEST_LOG="$tmp/log" OMARCHY_ARCH_CACHE="$tmp/cache" \
  OMARCHY_SNAPSHOT_MOUNT="$tmp/snapshot"
export OMARCHY_DEBIAN_PACMAN="$root/../adapters/pacman"
export XDG_CONFIG_HOME="$tmp/config"

[[ $("$root/bin/omarchy-channel-current") == stable ]]
"$root/bin/omarchy-channel-set" rc >/dev/null
[[ $("$root/bin/omarchy-channel-current") == rc ]]
"$root/bin/omarchy-channel-set" edge >/dev/null
[[ $("$root/bin/omarchy-channel-current") == edge ]]
"$root/bin/omarchy-channel-set" stable >/dev/null

"$root/bin/omarchy-arch" pacman example
rg -q 'sudo /usr/bin/pacman -S --needed -- example' "$TEST_LOG"
rg -q 'distrobox-export --app /usr/share/applications/example.desktop' "$TEST_LOG"
"$root/bin/omarchy-pkg-aur-add" example
rg -q 'yay -S --needed -- example' "$TEST_LOG"
"$root/bin/omarchy" pkg install --arch example
rg -q 'sudo /usr/bin/pacman -S --needed -- example' "$TEST_LOG"
"$root/bin/omarchy" pkg aur add example
rg -q 'yay -S --needed -- example' "$TEST_LOG"
"$root/bin/omarchy-update-available" | rg -q 'example/old'
"$root/bin/omarchy-snapshot" create
rg -q 'sudo timeshift --create --rsync --snapshot-device' "$TEST_LOG"
"$root/bin/omarchy-snapshot" configured
"$root/bin/omarchy-update"
rg -q 'sudo apt-get full-upgrade' "$TEST_LOG"
rg -q 'sudo /usr/bin/pacman -Syu' "$TEST_LOG"
rg -q 'yay -Sua' "$TEST_LOG"
"$root/bin/omarchy-arch" refresh-cache
rg -q '^example$' "$OMARCHY_ARCH_CACHE/arch-names"
"$root/bin/pacman" -Q example | rg -q '^example 1.0$'
"$root/bin/pacman" -Qi example | rg -q '^Name : example$'
"$root/bin/pacman" -Q bash example > "$tmp/union"
rg -q '^bash ' "$tmp/union"
rg -q '^example 1.0$' "$tmp/union"
if "$root/bin/pacman" -Q bash omarchy-test-missing-9ef857 > "$tmp/missing"; then
  echo 'A missing package incorrectly passed a multi-package query.' >&2
  exit 1
fi
if "$root/bin/pacman" -S example >/dev/null 2>&1; then
  echo 'The host package-query shim accepted a mutation.' >&2
  exit 1
fi
if "$root/bin/omarchy-snapshot" configured extra >/dev/null 2>&1; then
  echo 'Snapshot configured accepted unexpected arguments.' >&2
  exit 1
fi
if OMARCHY_SNAPSHOT_MOUNT="$tmp/nonexistent" "$root/bin/omarchy-snapshot" configured >/dev/null 2>&1; then
  echo 'Snapshot configured accepted a missing destination.' >&2
  exit 1
fi
if OMARCHY_SNAPSHOT_MOUNT='' "$root/bin/omarchy-snapshot" create >/dev/null 2>&1; then
  echo 'Snapshot creation accepted an unconfigured destination.' >&2
  exit 1
fi
cat >"$tmp/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  present) printf 'ii \tpresent\t1.0\tvirtual\n' ;;
  residual) printf 'rc \tresidual\t1.0\t\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/dpkg-query"
"$OMARCHY_DEBIAN_PACMAN" -Q present | rg -q '^present 1.0$'
for mode in -Q -Qq -Qi; do
  for package in residual missing; do
    if "$OMARCHY_DEBIAN_PACMAN" "$mode" "$package" > "$tmp/rejected"; then
      echo "Debian query $mode incorrectly accepted $package." >&2
      exit 1
    fi
    [[ ! -s $tmp/rejected ]]
  done
done
echo 'Bridge command tests passed.'
