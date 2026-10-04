#!/usr/bin/env bash
# Build a Debian 13 desktop around Omarchy's upstream Quattro configuration.
# Omarchy is Arch-specific; this installs Debian packages and Debian adapters.

set -Eeuo pipefail
umask 022

readonly OMARCHY_TAG="v4.0.4"
readonly OMARCHY_COMMIT="c668141e9c42b13c80c9ca4ea108e11708c5e8a5"
readonly OMARCHY_URL="https://github.com/basecamp/omarchy.git"
readonly OMARCHY_DIR="$HOME/.local/share/omarchy-debian/upstream"
readonly CACHE_DIR="$HOME/.cache/omarchy-debian"
readonly OMARCHY_PKGS_COMMIT="77212489259697324f331eeefe735848fdc552f9"
readonly OMARCHY_PKGS_URL="https://github.com/omacom/omarchy-pkgs.git"
readonly OMARCHY_PKGS_DIR="$CACHE_DIR/omarchy-pkgs"
readonly BACKPORTS_FILE="/etc/apt/sources.list.d/omarchy-debian-backports.sources"
readonly COMPONENTS_FILE="/etc/apt/sources.list.d/omarchy-debian-components.sources"
readonly BACKPORTS_COMPONENTS_FILE="/etc/apt/sources.list.d/omarchy-debian-backports-components.sources"
readonly PACKAGE_REPORT="$CACHE_DIR/package-install-report.log"

SOURCE_BUILDS=1
SOURCE_BUILD_LOG="$CACHE_DIR/source-builds.log"

say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./install-omarchy-debian.sh [--skip-source-builds]

Installs an Omarchy-like Hyprland desktop on a fresh Debian 13 (Trixie)
installation. Source builds for Omarchy companion apps are attempted by
default; use --skip-source-builds to skip those optional compilations.

The script does not partition disks, change bootloaders, or reboot the machine.
USAGE
}

while (($#)); do
  case "$1" in
    --skip-source-builds) SOURCE_BUILDS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "Run this as your regular desktop user. It will use sudo for system changes."
command -v sudo >/dev/null || die "Install sudo first, then run this script as your regular user."
command -v apt-get >/dev/null || die "This installer requires Debian's apt package manager."
[[ -r /etc/os-release ]] || die "Cannot identify this operating system."
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_CODENAME:-} == trixie ]] || \
  die "This installer targets Debian 13 Trixie only (detected ${PRETTY_NAME:-unknown})."

sudo -v
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons" "$CACHE_DIR"
export PATH="$HOME/.local/bin:$PATH"

say "Preparing Debian package sources"
# Trixie's default installer source often enables main and
# non-free-firmware. Add Debian's official contrib/non-free indexes too, plus
# backports for the Hyprland desktop stack. These files are installer-owned.
sudo tee "$COMPONENTS_FILE" >/dev/null <<'SOURCES'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: contrib non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: contrib non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES

if ! grep -Rqs 'trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  sudo tee "$BACKPORTS_FILE" >/dev/null <<'SOURCES'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
fi
sudo tee "$BACKPORTS_COMPONENTS_FILE" >/dev/null <<'SOURCES'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: contrib non-free
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES

if ! sudo apt-get update; then
  die "APT index refresh failed after configuring Debian Trixie, security, and backports sources. Check network and /etc/apt/sources.list.d/*.sources."
fi
if ! sudo apt-get install -y -- git curl ca-certificates; then
  die "Could not install required bootstrap tools (git, curl, ca-certificates) from the enabled Debian sources."
fi
: >"$PACKAGE_REPORT"

apt_candidate_available() {
  local target="$1" package="$2" candidate
  if [[ $target == "-" ]]; then
    candidate=$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
  else
    candidate=$(apt-cache -t "$target" policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
  fi
  [[ -n $candidate && $candidate != '(none)' ]]
}

apt_package_in_suite() {
  local suite="$1" package="$2"
  apt-cache madison "$package" 2>/dev/null | awk -v suite="$suite" 'index($0, suite) { found=1 } END { exit !found }'
}

apt_install_available() {
  local target="-"
  if [[ ${1:-} == --target ]]; then target="$2"; shift 2; fi
  local -a found=()
  local -a missing=()
  local -a target_args=()
  local package
  [[ $target == "-" ]] || target_args=(-t "$target")
  for package in "$@"; do
    if apt_candidate_available "$target" "$package"; then
      found+=("$package")
    else
      missing+=("$package")
    fi
  done
  if ((${#missing[@]})); then
    warn "No install candidate in the enabled Debian repositories; skipping: ${missing[*]}"
    for package in "${missing[@]}"; do printf 'skipped\t%s\tno candidate\n' "$package" >>"$PACKAGE_REPORT"; done
  fi
  if ((${#found[@]})); then
    if sudo apt-get "${target_args[@]}" install -y -- "${found[@]}"; then
      for package in "${found[@]}"; do printf 'installed\t%s\tbatch\n' "$package" >>"$PACKAGE_REPORT"; done
    else
      warn "APT could not install the package group; retrying each candidate separately."
      for package in "${found[@]}"; do
        if sudo apt-get "${target_args[@]}" install -y -- "$package"; then
          printf 'installed\t%s\tindividual retry\n' "$package" >>"$PACKAGE_REPORT"
        else
          warn "APT could not install $package; continuing with the remaining packages."
          printf 'failed\t%s\tAPT install failed\n' "$package" >>"$PACKAGE_REPORT"
        fi
      done
    fi
  fi
}

say "Installing Hyprland and Omarchy's Quickshell desktop core"
# These are Debian-maintained Trixie backports; -t selects the newer
# compositor, shell and portal from backports while resolving dependencies.
core_desktop_packages=(hyprland quickshell uwsm xdg-desktop-portal-hyprland)
for package in "${core_desktop_packages[@]}"; do
  if ! apt_package_in_suite trixie-backports "$package"; then
    printf 'failed\t%s\tnot present in trixie-backports\n' "$package" >>"$PACKAGE_REPORT"
    die "Required desktop package '$package' is not present in Trixie backports. Check the APT source files and update output. Package report: $PACKAGE_REPORT"
  fi
done
if ! sudo apt-get -t trixie-backports install -y -- "${core_desktop_packages[@]}"; then
  warn "The desktop core package batch failed; retrying each required package separately to identify the failing component."
  core_install_failures=()
  for package in "${core_desktop_packages[@]}"; do
    if sudo apt-get -t trixie-backports install -y -- "$package"; then
      printf 'installed\t%s\tindividual retry\n' "$package" >>"$PACKAGE_REPORT"
    else
      warn "Required desktop package '$package' could not be installed."
      printf 'failed\t%s\trequired desktop package install failed\n' "$package" >>"$PACKAGE_REPORT"
      core_install_failures+=("$package")
    fi
  done
  ((${#core_install_failures[@]} == 0)) || \
    die "Could not install required desktop packages: ${core_install_failures[*]}. See APT output and $PACKAGE_REPORT."
else
  for package in "${core_desktop_packages[@]}"; do printf 'installed\t%s\tbackports batch\n' "$package" >>"$PACKAGE_REPORT"; done
fi
for package in hyprlock hypridle hyprsunset hyprpicker hyprland-guiutils; do
  apt_install_available --target trixie-backports "$package"
done

say "Installing the Debian equivalents of Omarchy's base applications"
apt_install_available \
  sddm foot chromium neovim waybar wofi fzf gum jq git curl wget ca-certificates xdg-user-dirs \
  bolt less fontconfig \
  xdg-terminal-exec lazydocker dua-cli localsend mise obsidian moonlight-qt usage tobi-try \
  fonts-ia-writer python3-poetry-core ufw-docker gpu-screen-recorder-cli \
  systemd-oomd systemd-zram-generator \
  bash-completion build-essential clang cmake pkgconf python3 python3-gi \
  ruby-full lua5.1 luarocks ripgrep fd-find bat eza zoxide btop fastfetch tmux \
  lazygit plocate man-db unzip zip whois inxi ffmpeg ffmpegthumbnailer starship \
  tealdeer tree-sitter-cli fakeroot alsa-utils bluez-tools cups-pk-helper \
  gnome-themes-extra gvfs-backends gvfs-fuse inetutils inotify-tools libvips-tools libyaml-0-2 \
  libmariadb3 libpq5 llvm mpv-mpris nss-mdns pinta plymouth qemu-user-binfmt \
  qt6-image-formats-plugins socat udiskie wireless-regdb yaru-theme-gtk yaru-theme-icon \
  imagemagick imv mpv yt-dlp tesseract-ocr tesseract-ocr-eng qrencode zbar-tools \
  grim slurp wl-clipboard wtype brightnessctl ddcutil playerctl pamixer \
  pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber pavucontrol \
  xdg-desktop-portal xdg-desktop-portal-gtk qt6-wayland \
  network-manager bluez blueman power-profiles-daemon \
  gnome-keyring libsecret-tools nautilus nautilus-python sushi \
  gnome-disk-utility evince libreoffice obs-studio kdenlive xournalpp \
  cups cups-filters system-config-printer avahi-daemon \
  fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk fonts-font-awesome \
  fonts-jetbrains-mono fonts-ibm-plex fonts-liberation \
  dosfstools exfatprogs flatpak ufw

# Quickshell's base package brings Quick, Controls and Layouts; Omarchy imports
# Effects and Shapes directly, so request those QML modules explicitly too.
apt_install_available qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-effects qml6-module-qtquick-shapes

apt_install_available docker.io docker-compose-v2 docker-buildx libglib2.0-bin \
  gsettings-desktop-schemas
apt_install_available fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-qt5
apt_install_available fcitx5-frontend-gtk4 fcitx5-frontend-qt6
apt_install_available nodejs npm golang-go rustup meson ninja-build cmake \
  qt6-base-dev qt6-declarative-dev qt6-multimedia-dev qt6-tools-dev \
  liblayershellqtinterface-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
  libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev libepoxy-dev \
  libfontconfig1-dev libwayland-dev wayland-protocols libmpv-dev

if command -v systemctl >/dev/null 2>&1; then
  say "Enabling desktop services"
  for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service \
    cups.service avahi-daemon.service docker.socket systemd-oomd.service; do
    if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
      sudo systemctl enable "$unit" || warn "Could not enable $unit"
    fi
  done
fi

say "Fetching Omarchy's released Quattro configuration and shell"
if [[ -d $OMARCHY_DIR ]]; then
  current_commit=$(git -C "$OMARCHY_DIR" rev-parse HEAD 2>/dev/null || true)
  [[ $current_commit == "$OMARCHY_COMMIT" ]] || \
    die "$OMARCHY_DIR already exists and is not the expected Omarchy $OMARCHY_TAG checkout; move it aside before retrying."
else
  mkdir -p "${OMARCHY_DIR%/*}"
  git clone --filter=blob:none --no-checkout "$OMARCHY_URL" "$OMARCHY_DIR"
  git -C "$OMARCHY_DIR" fetch --depth=1 origin "$OMARCHY_COMMIT"
  git -C "$OMARCHY_DIR" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$OMARCHY_DIR" rev-parse HEAD) == "$OMARCHY_COMMIT" ]] || die "Omarchy source revision did not match the pinned release."

install_omarchy_nvim_config() {
  local starter_archive="$CACHE_DIR/sources/lazyvim-starter-main.tar.gz"
  local starter_sha=d865d50211358358d3c3c1e356773c1e3de1e8964215d85eb1b4c77521e17488
  local package_dir="$OMARCHY_PKGS_DIR/pkgbuilds/omarchy-nvim"
  local staging="$CACHE_DIR/build/lazyvim-starter"
  mkdir -p "${starter_archive%/*}" "${staging%/*}"
  if [[ ! -d $OMARCHY_PKGS_DIR/.git ]]; then
    git clone --filter=blob:none --no-checkout "$OMARCHY_PKGS_URL" "$OMARCHY_PKGS_DIR" || return 1
  fi
  git -C "$OMARCHY_PKGS_DIR" fetch --depth=1 origin "$OMARCHY_PKGS_COMMIT" || return 1
  git -C "$OMARCHY_PKGS_DIR" sparse-checkout init --cone || return 1
  git -C "$OMARCHY_PKGS_DIR" sparse-checkout set pkgbuilds/omarchy-nvim || return 1
  git -C "$OMARCHY_PKGS_DIR" checkout --detach FETCH_HEAD || return 1
  [[ $(git -C "$OMARCHY_PKGS_DIR" rev-parse HEAD) == "$OMARCHY_PKGS_COMMIT" ]] || return 1
  [[ -d $package_dir/lua && -d $package_dir/plugin && -f $package_dir/lazyvim.json ]] || return 1

  if [[ ! -f $starter_archive ]] || ! printf '%s  %s\n' "$starter_sha" "$starter_archive" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$starter_archive"
    curl --proto '=https' --tlsv1.2 -fsSL \
      https://github.com/LazyVim/starter/archive/refs/heads/main.tar.gz -o "$starter_archive" || return 1
  fi
  printf '%s  %s\n' "$starter_sha" "$starter_archive" | sha256sum -c - >/dev/null || return 1
  rm -rf "$staging"
  mkdir -p "$staging"
  tar -xzf "$starter_archive" --strip-components=1 -C "$staging" || return 1
  rm -rf "$staging/.git"

  if [[ -e $HOME/.config/nvim || -L $HOME/.config/nvim ]]; then
    mkdir -p "$CONFIG_BACKUP"
    mv -- "$HOME/.config/nvim" "$CONFIG_BACKUP/nvim"
  fi
  cp -a "$staging" "$HOME/.config/nvim"
  cp -a "$package_dir/lua" "$package_dir/plugin" "$HOME/.config/nvim/"
  install -m 0644 "$package_dir/lazyvim.json" "$HOME/.config/nvim/lazyvim.json"
  mkdir -p "$HOME/.config/nvim/lua/plugins"
  ln -sfn ../../../../.local/state/omarchy/current/theme/neovim.lua \
    "$HOME/.config/nvim/lua/plugins/theme.lua"
}

CONFIG_BACKUP="$HOME/.config/omarchy-debian-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/.config"
say "Seeding Omarchy's LazyVim editor configuration"
install_omarchy_nvim_config || warn "Could not fetch the pinned Omarchy Neovim configuration; Neovim will use its Debian default."

say "Installing Omarchy user defaults and Debian session entry"
for source_path in "$OMARCHY_DIR"/config/*; do
  [[ -e $source_path ]] || continue
  config_name=${source_path##*/}
  target_path="$HOME/.config/$config_name"
  if [[ -e $target_path || -L $target_path ]]; then
    mkdir -p "$CONFIG_BACKUP"
    mv -- "$target_path" "$CONFIG_BACKUP/"
  fi
  cp -a -- "$source_path" "$target_path"
  if [[ $config_name == autostart ]]; then
    rm -f "$target_path/limine-snapper-notify.desktop"
  fi
done

cat >"$OMARCHY_DIR/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
# Read-only pacman query compatibility for Omarchy menu guards on Debian.
# Any package-changing pacman operation is deliberately refused.
set -euo pipefail

debian_name() {
  case "$1" in
    nvim) echo neovim ;;
    avahi) echo avahi-daemon ;;
    bluez-utils) echo bluez ;;
    libreoffice-fresh) echo libreoffice ;;
    docker) echo docker.io ;;
    docker-compose) echo docker-compose-v2 ;;
    fd) echo fd-find ;;
    fcitx5-gtk) echo fcitx5-frontend-gtk3 ;;
    fcitx5-qt) echo fcitx5-frontend-qt5 ;;
    libsecret) echo libsecret-tools ;;
    libyaml) echo libyaml-0-2 ;;
    mariadb-libs) echo libmariadb3 ;;
    networkmanager) echo network-manager ;;
    noto-fonts) echo fonts-noto-core ;;
    noto-fonts-cjk) echo fonts-noto-cjk ;;
    noto-fonts-emoji) echo fonts-noto-color-emoji ;;
    python-gobject) echo python3-gi ;;
    python-poetry-core) echo python3-poetry-core ;;
    lua51) echo lua5.1 ;;
    postgresql-libs) echo libpq5 ;;
    qemu-user-static-binfmt) echo qemu-user-binfmt ;;
    qt6-imageformats) echo qt6-image-formats-plugins ;;
    tesseract) echo tesseract-ocr ;;
    tesseract-data-eng) echo tesseract-ocr-eng ;;
    tldr) echo tealdeer ;;
    woff2-font-awesome) echo fonts-font-awesome ;;
    yaru-icon-theme) echo yaru-theme-icon ;;
    zbar) echo zbar-tools ;;
    *) echo "$1" ;;
  esac
}

mode=${1:-}
[[ $mode == -Q* ]] || { echo "pacman is unavailable on Debian; use apt or omarchy-pkg-add." >&2; exit 2; }
query_info=0
query_quiet=0
args=()
mode_flags=${mode#-Q}
[[ $mode_flags == *i* ]] && query_info=1
[[ $mode_flags == *q* ]] && query_quiet=1
shift
while (($#)); do
  case "$1" in
    -i|-Qi) query_info=1 ;;
    -q|-Qq) query_quiet=1 ;;
    -Q*)
      mode_flags=${1#-Q}
      [[ $mode_flags == *i* ]] && query_info=1
      [[ $mode_flags == *q* ]] && query_quiet=1
      ;;
    --) ;;
    -*) ;;
    *) args+=("$(debian_name "$1")") ;;
  esac
  shift
done

if (( query_info )); then
  packages=("${args[@]}")
  if ((${#packages[@]} == 0)); then
    mapfile -t packages < <(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null)
  fi
  for package in "${packages[@]}"; do
    dpkg-query -W -f='Name : ${binary:Package}\nProvides : ${Provides}\n\n' "$package" 2>/dev/null || true
  done
elif ((${#args[@]})); then
  for package in "${args[@]}"; do
    if dpkg-query -W -f='${binary:Package}\n' "$package" 2>/dev/null; then
      (( query_quiet )) || dpkg-query -W -f='${binary:Package} ${Version}\n' "$package"
    else
      exit 1
    fi
  done
else
  if (( query_quiet )); then
    dpkg-query -W -f='${binary:Package}\n'
  else
    dpkg-query -W -f='${binary:Package} ${Version}\n'
  fi
fi
PACMAN
chmod 755 "$OMARCHY_DIR/bin/pacman"

cat >"$OMARCHY_DIR/bin/omarchy-pkg-add" <<'PKGADD'
#!/usr/bin/env bash
set -euo pipefail
debian_name() {
  case "$1" in
    nvim) echo neovim ;;
    avahi) echo avahi-daemon ;;
    bluez-utils) echo bluez ;;
    libreoffice-fresh) echo libreoffice ;;
    docker) echo docker.io ;;
    docker-compose) echo docker-compose-v2 ;;
    fd) echo fd-find ;;
    fcitx5-gtk) echo fcitx5-frontend-gtk3 ;;
    fcitx5-qt) echo fcitx5-frontend-qt5 ;;
    libsecret) echo libsecret-tools ;;
    libyaml) echo libyaml-0-2 ;;
    mariadb-libs) echo libmariadb3 ;;
    networkmanager) echo network-manager ;;
    noto-fonts) echo fonts-noto-core ;;
    noto-fonts-cjk) echo fonts-noto-cjk ;;
    noto-fonts-emoji) echo fonts-noto-color-emoji ;;
    python-gobject) echo python3-gi ;;
    python-poetry-core) echo python3-poetry-core ;;
    lua51) echo lua5.1 ;;
    postgresql-libs) echo libpq5 ;;
    qemu-user-static-binfmt) echo qemu-user-binfmt ;;
    qt6-imageformats) echo qt6-image-formats-plugins ;;
    tesseract) echo tesseract-ocr ;;
    tesseract-data-eng) echo tesseract-ocr-eng ;;
    tldr) echo tealdeer ;;
    woff2-font-awesome) echo fonts-font-awesome ;;
    yaru-icon-theme) echo yaru-theme-icon ;;
    zbar) echo zbar-tools ;;
    *) echo "$1" ;;
  esac
}
packages=()
for requested in "$@"; do
  candidate=$(debian_name "$requested")
  if apt-cache show "$candidate" >/dev/null 2>&1; then
    packages+=("$candidate")
  else
    echo "No Debian package mapping for '$requested'; skipped." >&2
  fi
done
((${#packages[@]})) || { echo "No requested packages have Debian mappings." >&2; exit 1; }
exec sudo apt-get install -- "${packages[@]}"
PKGADD
chmod 755 "$OMARCHY_DIR/bin/omarchy-pkg-add"

cat >"$OMARCHY_DIR/bin/omarchy-pkg-remove" <<'PKGREMOVE'
#!/usr/bin/env bash
set -euo pipefail
debian_name() {
  case "$1" in
    nvim) echo neovim ;;
    avahi) echo avahi-daemon ;;
    bluez-utils) echo bluez ;;
    libreoffice-fresh) echo libreoffice ;;
    docker) echo docker.io ;;
    docker-compose) echo docker-compose-v2 ;;
    fd) echo fd-find ;;
    fcitx5-gtk) echo fcitx5-frontend-gtk3 ;;
    fcitx5-qt) echo fcitx5-frontend-qt5 ;;
    libsecret) echo libsecret-tools ;;
    libyaml) echo libyaml-0-2 ;;
    mariadb-libs) echo libmariadb3 ;;
    networkmanager) echo network-manager ;;
    noto-fonts) echo fonts-noto-core ;;
    noto-fonts-cjk) echo fonts-noto-cjk ;;
    noto-fonts-emoji) echo fonts-noto-color-emoji ;;
    python-gobject) echo python3-gi ;;
    python-poetry-core) echo python3-poetry-core ;;
    lua51) echo lua5.1 ;;
    postgresql-libs) echo libpq5 ;;
    qemu-user-static-binfmt) echo qemu-user-binfmt ;;
    qt6-imageformats) echo qt6-image-formats-plugins ;;
    tesseract) echo tesseract-ocr ;;
    tesseract-data-eng) echo tesseract-ocr-eng ;;
    tldr) echo tealdeer ;;
    woff2-font-awesome) echo fonts-font-awesome ;;
    yaru-icon-theme) echo yaru-theme-icon ;;
    zbar) echo zbar-tools ;;
    *) echo "$1" ;;
  esac
}
packages=()
if (($# == 0)); then
  command -v fzf >/dev/null || { echo "Install fzf to use the interactive removal picker." >&2; exit 1; }
  package=$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | sort -u | \
    fzf --prompt='Installed Debian package to remove > ') || exit 0
  [[ -n $package ]] || exit 0
  set -- "$package"
fi
for requested in "$@"; do packages+=("$(debian_name "$requested")"); done
exec sudo apt-get remove -- "${packages[@]}"
PKGREMOVE
chmod 755 "$OMARCHY_DIR/bin/omarchy-pkg-remove"

cat >"$OMARCHY_DIR/bin/omarchy-pkg-present" <<'PKGPRESENT'
#!/usr/bin/env bash
set -euo pipefail
for package in "$@"; do pacman -Q -- "$package" >/dev/null 2>&1 || exit 1; done
PKGPRESENT
cat >"$OMARCHY_DIR/bin/omarchy-pkg-missing" <<'PKGMISSING'
#!/usr/bin/env bash
set -euo pipefail
for package in "$@"; do pacman -Q -- "$package" >/dev/null 2>&1 || exit 0; done
exit 1
PKGMISSING
chmod 755 "$OMARCHY_DIR/bin/omarchy-pkg-present" "$OMARCHY_DIR/bin/omarchy-pkg-missing"

cat >"$OMARCHY_DIR/bin/omarchy-pkg-install" <<'PKGINSTALL'
#!/usr/bin/env bash
set -euo pipefail
command -v fzf >/dev/null || { echo "Install fzf to use the interactive package picker." >&2; exit 1; }
package=$(apt-cache pkgnames | sort -u | fzf --prompt='Debian package > ' --preview='apt-cache show {} 2>/dev/null | sed -n "1,18p"') || exit 0
[[ -n $package ]] && exec sudo apt-get install -- "$package"
PKGINSTALL
chmod 755 "$OMARCHY_DIR/bin/omarchy-pkg-install"

cat >"$OMARCHY_DIR/bin/omarchy-update" <<'UPDATE'
#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
exec sudo apt-get full-upgrade
UPDATE
chmod 755 "$OMARCHY_DIR/bin/omarchy-update"

cat >"$OMARCHY_DIR/bin/omarchy-update-system-pkgs" <<'UPDATESYSTEM'
#!/usr/bin/env bash
set -euo pipefail
exec omarchy-update "$@"
UPDATESYSTEM
chmod 755 "$OMARCHY_DIR/bin/omarchy-update-system-pkgs"

cat >"$OMARCHY_DIR/bin/omarchy-update-available" <<'UPDATEAVAILABLE'
#!/usr/bin/env bash
set -euo pipefail
apt list --upgradable 2>/dev/null | sed '1d' || true
UPDATEAVAILABLE
chmod 755 "$OMARCHY_DIR/bin/omarchy-update-available"

cat >"$OMARCHY_DIR/bin/omarchy-version" <<VERSION
#!/usr/bin/env bash
echo "${OMARCHY_TAG#v}-debian"
VERSION
chmod 755 "$OMARCHY_DIR/bin/omarchy-version"

cat >"$OMARCHY_DIR/bin/omarchy-version-branch" <<'VERSIONBRANCH'
#!/usr/bin/env bash
echo "Debian"
VERSIONBRANCH
cat >"$OMARCHY_DIR/bin/omarchy-version-channel" <<'VERSIONCHANNEL'
#!/usr/bin/env bash
echo "Debian"
VERSIONCHANNEL
cat >"$OMARCHY_DIR/bin/omarchy-version-pkgs" <<'VERSIONPKGS'
#!/usr/bin/env bash
start_date=$(grep -h '^[[:space:]]*Start-Date:' /var/log/apt/history.log* 2>/dev/null | tail -1 | sed 's/^[[:space:]]*Start-Date:[[:space:]]*//')
if [[ -n $start_date ]]; then
  date -d "$start_date" '+%A, %B %d %Y at %H:%M' 2>/dev/null || echo "$start_date"
else
  echo "No APT history yet"
fi
VERSIONPKGS
chmod 755 "$OMARCHY_DIR/bin/omarchy-version-branch" \
  "$OMARCHY_DIR/bin/omarchy-version-channel" "$OMARCHY_DIR/bin/omarchy-version-pkgs"

for unsupported_command in omarchy-upgrade-to-quattro omarchy-system-factory-reset \
  omarchy-system-factory-reset-finish; do
  cat >"$OMARCHY_DIR/bin/$unsupported_command" <<'UNSUPPORTED'
#!/usr/bin/env bash
echo "This Omarchy command modifies Arch/Limine/Snapper system state and is disabled on Debian." >&2
exit 2
UNSUPPORTED
  chmod 755 "$OMARCHY_DIR/bin/$unsupported_command"
done

cat >"$OMARCHY_DIR/bin/omarchy-pkg-aur-install" <<'AURUNAVAILABLE'
#!/usr/bin/env bash
echo "AUR packages are unavailable on Debian; use omarchy-pkg-add for Debian packages." >&2
exit 2
AURUNAVAILABLE
chmod 755 "$OMARCHY_DIR/bin/omarchy-pkg-aur-install"

cat >"$OMARCHY_DIR/bin/omarchy-provision-first-run" <<'FIRSTRUN'
#!/usr/bin/env bash
set -Eeuo pipefail
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy-debian/upstream}"
export OMARCHY_PATH
state_file="$HOME/.local/state/omarchy/debian-first-run.done"
if [[ -e $state_file && ${1:-} != --force ]]; then exit 0; fi
mkdir -p "$HOME/Downloads" "$HOME/Pictures" "$HOME/Videos"
mkdir -p "$HOME/.local/state/omarchy/toggles/hypr" \
  "$HOME/.local/share/nautilus-python/extensions" "$HOME/.config/omarchy/branding"
[[ -e $HOME/.local/state/omarchy/toggles/hypr/flags.lua ]] || \
  cp -a "$OMARCHY_PATH/default/hypr/toggles/flags.lua" "$HOME/.local/state/omarchy/toggles/hypr/flags.lua"
for extension in localsend.py transcode.py; do
  [[ -e $HOME/.local/share/nautilus-python/extensions/$extension ]] || \
    cp -a "$OMARCHY_PATH/default/nautilus-python/extensions/$extension" \
      "$HOME/.local/share/nautilus-python/extensions/$extension"
done
[[ -e $HOME/.config/omarchy/branding/screensaver.txt ]] || \
  cp -a "$OMARCHY_PATH/logo.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
[[ -e $HOME/.config/omarchy/branding/about.txt ]] || \
  cp -a "$OMARCHY_PATH/icon.txt" "$HOME/.config/omarchy/branding/about.txt"
command -v xdg-user-dirs-update >/dev/null && xdg-user-dirs-update || true
if [[ ! -s $HOME/.local/state/omarchy/current/theme.name ]]; then
  OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"
fi
omarchy-theme-set-pi --activate >/dev/null 2>&1 || true

for step in gnome-theme.sh gtk-primary-paste.sh default-keyring.sh; do
  [[ -x $OMARCHY_PATH/install/user/$step || -f $OMARCHY_PATH/install/user/$step ]] || continue
  bash "$OMARCHY_PATH/install/user/$step" || echo "Omarchy first-run step failed: $step" >&2
done

if [[ ! -e $HOME/.XCompose && -r $OMARCHY_PATH/default/xcompose ]]; then
  printf '# Generated by Omarchy on Debian\ninclude "/usr/share/omarchy/default/xcompose"\n' >"$HOME/.XCompose"
fi

if [[ -f $OMARCHY_PATH/install/user/first-run/enable-user-units.sh ]]; then
  bash "$OMARCHY_PATH/install/user/first-run/enable-user-units.sh" || \
    echo "Could not enable every Omarchy user service; see systemctl --user status." >&2
fi
if command -v omarchy-audio-tuning >/dev/null 2>&1; then
  bash "$OMARCHY_PATH/install/user/first-run/audio-tuning.sh" || true
fi

if command -v omarchy-notification-wait >/dev/null 2>&1; then
  omarchy-notification-wait || true
  bash "$OMARCHY_PATH/install/user/first-run/welcome.sh" || true
  bash "$OMARCHY_PATH/install/user/first-run/wifi.sh" || true
fi

mkdir -p "${state_file%/*}"
touch "$state_file"
FIRSTRUN
chmod 755 "$OMARCHY_DIR/bin/omarchy-provision-first-run"

if [[ -f $HOME/.bashrc ]] && ! grep -q 'OMARCHY_DEBIAN_SETUP' "$HOME/.bashrc"; then
  cat >>"$HOME/.bashrc" <<'BASHRC'

# OMARCHY_DEBIAN_SETUP
export OMARCHY_PATH=/usr/share/omarchy
export PATH="$HOME/.local/bin:$PATH"
[[ -r /usr/share/omarchy/default/bashrc ]] && source /usr/share/omarchy/default/bashrc
BASHRC
fi
if [[ -f $HOME/.profile ]] && ! grep -q 'OMARCHY_DEBIAN_SETUP' "$HOME/.profile"; then
  cat >>"$HOME/.profile" <<'PROFILE'

# OMARCHY_DEBIAN_SETUP
export OMARCHY_PATH=/usr/share/omarchy
export PATH="$HOME/.local/bin:$PATH"
PROFILE
fi

for command_link in fd bat; do
  case "$command_link" in
    fd) target=/usr/bin/fdfind ;;
    bat) target=/usr/bin/batcat ;;
  esac
  if [[ -x $target && ! -e $HOME/.local/bin/$command_link ]]; then
    ln -s "$target" "$HOME/.local/bin/$command_link"
  fi
done

# Quickshell's lock screen uses its own PAM service name. Debian's common-* PAM
# stacks keep authentication policy in the standard Debian-managed files.
sudo tee /etc/pam.d/omarchy-lock-password >/dev/null <<'PAM'
#%PAM-1.0
auth    include common-auth
account include common-account
PAM

cat <<'DESKTOP' | sudo tee /usr/share/wayland-sessions/omarchy-debian.desktop >/dev/null
[Desktop Entry]
Name=Omarchy on Debian
Comment=Omarchy Quattro desktop running on Debian 13
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
TryExec=uwsm
Type=Application
DesktopNames=Hyprland;Omarchy
DESKTOP

if [[ ! -e /etc/systemd/system/display-manager.service ]] && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable sddm.service || warn "Could not enable SDDM; select it as the display manager manually."
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi
if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true; fi

install_nerd_font() {
  local archive="$CACHE_DIR/sources/JetBrainsMono-3.5.1.tar.xz"
  local unpack="$CACHE_DIR/build/JetBrainsMono-3.5.1"
  local checksum=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf
  mkdir -p "${archive%/*}" "$unpack"
  if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$archive"
    curl --proto '=https' --tlsv1.2 -fsSL \
      https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz \
      -o "$archive" || return 1
  fi
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || return 1
  rm -rf "$unpack"
  mkdir -p "$unpack"
  tar -xJf "$archive" -C "$unpack" \
    JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFont-Bold.ttf \
    JetBrainsMonoNerdFont-Italic.ttf JetBrainsMonoNerdFont-BoldItalic.ttf OFL.txt
  sudo install -d -m 0755 /usr/local/share/fonts/omarchy-debian
  sudo install -m 0644 "$unpack"/JetBrainsMonoNerdFont-*.ttf /usr/local/share/fonts/omarchy-debian/
  sudo install -m 0644 "$unpack/OFL.txt" /usr/local/share/fonts/omarchy-debian/OFL.txt
  command -v fc-cache >/dev/null 2>&1 && sudo fc-cache -f /usr/local/share/fonts/omarchy-debian >/dev/null 2>&1 || true
}

say "Installing Omarchy's Nerd Font used by its terminal and shell UI"
install_nerd_font || warn "Could not install the pinned JetBrainsMono Nerd Font; icons may use fallback glyphs."

install_localsend() {
  local archive="$CACHE_DIR/sources/localsend-1.18.2-$(dpkg --print-architecture).deb"
  local url checksum
  if dpkg-query -W -f='${Status}' localsend 2>/dev/null | grep -q 'install ok installed'; then return 0; fi
  case $(dpkg --print-architecture) in
    amd64)
      url=https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-x86-64.deb
      checksum=cc42a4f3eacdcb25ec31f0016b1272acb003145ab30484db8965450e20c72cd2
      ;;
    arm64)
      url=https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-arm-64.deb
      checksum=bbd8347b7979f936d3bae176a3f0d9b81431605707c585270d6240f7670feb1f
      ;;
    *) warn "LocalSend's upstream Debian build is unavailable for $(dpkg --print-architecture); skipping it."; return 0 ;;
  esac
  mkdir -p "${archive%/*}"
  if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$archive"
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$archive" || return 1
  fi
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || return 1
  sudo apt-get install -y "$archive"
}

say "Installing LocalSend's upstream Debian build when Trixie has no package"
install_localsend || warn "LocalSend was not installed; see the network/package error above."

install_mise() {
  local version=2026.9.12 suffix checksum archive unpack binary
  if command -v mise >/dev/null 2>&1; then return 0; fi
  case $(dpkg --print-architecture) in
    amd64) suffix=x64; checksum=30c79a0a24d8f0ad80e6c9b11ec54816be2a9b77e7eeae32c1267a5b9d34d3d7 ;;
    arm64) suffix=arm64; checksum=7bc2a5558b787a33f22e4b5955cfec58871ad3723658418ad3d2cdf5a0e693b9 ;;
    *) warn "Mise upstream binaries are not published for $(dpkg --print-architecture); skipping it."; return 0 ;;
  esac
  archive="$CACHE_DIR/sources/mise-v$version-linux-$suffix.tar.xz"
  unpack="$CACHE_DIR/build/mise-v$version-linux-$suffix"
  mkdir -p "${archive%/*}" "${unpack%/*}"
  if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$archive"
    curl --proto '=https' --tlsv1.2 -fsSL \
      "https://github.com/jdx/mise/releases/download/v$version/mise-v$version-linux-$suffix.tar.xz" \
      -o "$archive" || return 1
  fi
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || return 1
  rm -rf "$unpack"
  mkdir -p "$unpack"
  tar -xJf "$archive" -C "$unpack"
  binary=$(find "$unpack" -type f -path '*/bin/mise' -print -quit)
  [[ -n $binary ]] || return 1
  sudo install -Dm0755 "$binary" /usr/local/bin/mise
  sudo install -Dm0644 /dev/null /usr/local/lib/mise/.disable-self-update
}

say "Installing Mise from Debian or its pinned upstream release"
install_mise || warn "Mise was not installed; Omarchy's version-manager integration will be unavailable."

install_ufw_docker() {
  local archive="$CACHE_DIR/sources/ufw-docker-251123.tar.gz"
  local checksum=d4ac771a83a5f7bd328c8d30094a45752dd1b38de7f2d7f5269e369289d9e8ef189b020b97e4d93025d9d7ad61757cda31f80e548e8611b77653f75e731400b7
  local work="$CACHE_DIR/build/ufw-docker-251123"
  command -v ufw-docker >/dev/null 2>&1 && return 0
  mkdir -p "${archive%/*}"
  if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | b2sum -c - >/dev/null 2>&1; then
    rm -f "$archive"
    curl --proto '=https' --tlsv1.2 -fsSL \
      https://github.com/chaifeng/ufw-docker/archive/refs/tags/251123.tar.gz -o "$archive" || return 1
  fi
  printf '%s  %s\n' "$checksum" "$archive" | b2sum -c - >/dev/null || return 1
  rm -rf "$work"
  mkdir -p "$work"
  tar -xzf "$archive" --strip-components=1 -C "$work" || return 1
  sudo install -Dm0755 "$work/ufw-docker" /usr/local/bin/ufw-docker
}

say "Installing the pinned UFW/Docker helper without changing firewall rules"
install_ufw_docker || warn "Could not install ufw-docker; install it manually before relying on UFW with Docker."

build_source_extras() {
  local build_root="$CACHE_DIR/build"
  mkdir -p "$build_root" "$HOME/.local/bin" "$HOME/.local/share/applications"

  apt_install_available rustup golang-go git curl cmake ninja-build meson \
    pkgconf build-essential qt6-base-dev qt6-declarative-dev qt6-multimedia-dev \
    qt6-tools-dev liblayershellqtinterface-dev libwayland-dev wayland-protocols \
    libmpv-dev libasound2-dev libflac-dev libvorbis-dev libogg-dev libmpg123-dev \
    libsystemd-dev libsocat-dev libgtk-3-dev libwebkit2gtk-4.1-dev nodejs npm \
    libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev libepoxy-dev libfontconfig1-dev \
    libtesseract-dev libglib2.0-dev libwayland-bin libavcodec-dev libavformat-dev \
    libavutil-dev libx11-dev libxcomposite-dev libxrandr-dev libxfixes-dev \
    libpulse-dev libswresample-dev libavfilter-dev libva-dev libdrm-dev libcap-dev \
    libpipewire-0.3-dev libspa-0.2-dev libdbus-1-dev libxdamage-dev libvulkan-dev \
    libegl1-mesa-dev libgl1-mesa-dev libopus-dev libsdl2-dev libsdl2-ttf-dev \
    libssl-dev libswscale-dev libvdpau-dev libxkbcommon-dev libqt6svg6-dev \
    qml6-module-qtquick-templates qml6-module-qtqml-workerscript \
    qml6-module-qtquick-window

  if command -v rustup >/dev/null 2>&1; then
    rustup toolchain install stable --profile minimal >/dev/null || \
      echo "Stable Rust toolchain unavailable; Rust app builds may be skipped." | tee -a "$SOURCE_BUILD_LOG"
  fi

  build_archive() {
    local name="$1" version="$2" repo="$3" checksum="$4" builder="$5" tag_prefix="${6-v}"
    local archive="$CACHE_DIR/sources/$name-$version.tar.gz"
    local work="$build_root/$name-$version"
    mkdir -p "${archive%/*}"
    if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null 2>&1; then
      rm -f "$archive"
      curl --proto '=https' --tlsv1.2 -fsSL \
        "https://github.com/$repo/archive/refs/tags/$tag_prefix$version.tar.gz" -o "$archive" || return 1
    fi
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || {
      echo "$name: source checksum mismatch" | tee -a "$SOURCE_BUILD_LOG" >&2
      return 1
    }
    rm -rf "$work"
    mkdir -p "$work"
    tar -xzf "$archive" --strip-components=1 -C "$work" || return 1
    "$builder" "$work" || return 1
    echo "$name $version: built" | tee -a "$SOURCE_BUILD_LOG"
  }

  try_build() {
    local name="$1"
    shift
    if "$@" >>"$SOURCE_BUILD_LOG" 2>&1; then
      echo "$name: built successfully" | tee -a "$SOURCE_BUILD_LOG"
      return 0
    else
      local status=$?
      echo "$name: build failed (exit $status); continuing" | tee -a "$SOURCE_BUILD_LOG" >&2
      return 0
    fi
  }

  install_desktop() {
    local name="$1" title="$2" command_name="$3" icon="$4"
    cat >"$HOME/.local/share/applications/$name.desktop" <<EOF_DESKTOP
[Desktop Entry]
Name=$title
Exec=$command_name
Icon=$icon
Terminal=false
Type=Application
Categories=Utility;
EOF_DESKTOP
  }

  build_asdcontrol() {
    (cd "$1" && make)
    install -m 755 "$1/asdcontrol" "$HOME/.local/bin/asdcontrol"
  }
  build_cliamp() {
    (cd "$1" && go build -trimpath -buildmode=pie -ldflags='-s -w' -o "$HOME/.local/bin/cliamp" .)
  }
  build_herdr() {
    local zig_arch zig_sha zig_version=0.16.0 zig_archive zig_dir
    case $(dpkg --print-architecture) in
      amd64) zig_arch=x86_64; zig_sha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
      arm64) zig_arch=aarch64; zig_sha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;;
      *) echo "Herdr: upstream only supplies a Zig toolchain for amd64 and arm64" >&2; return 1 ;;
    esac
    zig_archive="$CACHE_DIR/sources/zig-$zig_arch-linux-$zig_version.tar.xz"
    zig_dir="$build_root/zig-$zig_arch-linux-$zig_version"
    if [[ ! -f $zig_archive ]] || ! printf '%s  %s\n' "$zig_sha" "$zig_archive" | sha256sum -c - >/dev/null 2>&1; then
      rm -f "$zig_archive"
      curl --proto '=https' --tlsv1.2 -fsSL \
        "https://ziglang.org/download/$zig_version/zig-$zig_arch-linux-$zig_version.tar.xz" \
        -o "$zig_archive" || return 1
    fi
    printf '%s  %s\n' "$zig_sha" "$zig_archive" | sha256sum -c - >/dev/null || return 1
    rm -rf "$zig_dir"
    tar -xJf "$zig_archive" -C "$build_root" || return 1
    (cd "$1" && ZIG="$zig_dir/zig" ZIG_GLOBAL_CACHE_DIR="$build_root/zig-cache" \
      cargo +stable build --locked --release)
    install -m 755 "$1/target/release/herdr" "$HOME/.local/bin/herdr"
  }
  build_omacalc() {
    (cd "$1" && ./bin/build)
    install -m 755 "$1/build/omacalc" "$HOME/.local/bin/omacalc"
    install_desktop omacalc "OmaCalc" omacalc accessories-calculator
  }
  build_omacut() {
    (cd "$1" && ./bin/build)
    install -m 755 "$1/build/omacut" "$HOME/.local/bin/omacut"
    install_desktop omacut "OmaCut" omacut applications-multimedia
  }
  build_omawrite() {
    (cd "$1" && ./bin/build)
    install -m 755 "$1/build/omawrite" "$HOME/.local/bin/omawrite"
    install_desktop omawrite "OmaWrite" omawrite accessories-text-editor
  }
  build_omasnap() {
    local prefix="$HOME/.local"
    cmake -S "$1" -B "$1/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build "$1/build" --parallel "$(nproc)"
    cmake --install "$1/build"
  }
  build_owe() {
    meson setup "$1/build" "$1" --buildtype=release --prefix="$HOME/.local"
    meson compile -C "$1/build"
    meson install -C "$1/build"
  }
  build_ttfx() {
    (cd "$1" && cargo +stable build --locked --release)
    install -m 755 "$1/target/release/ttfx" "$HOME/.local/bin/ttfx"
  }
  build_tensaku() {
    (cd "$1" && cargo +stable build --locked --release --features ci-release)
    install -m 755 "$1/target/release/tensaku" "$HOME/.local/bin/tensaku"
    install -m 755 "$1/assets/tensaku-edit" "$HOME/.local/bin/tensaku-edit"
    install -Dm644 "$1/dev.tensaku.Tensaku.desktop" \
      "$HOME/.local/share/applications/dev.tensaku.Tensaku.desktop"
    install -Dm644 "$1/assets/tensaku.svg" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/dev.tensaku.Tensaku.svg"
    install -Dm644 "$OMARCHY_DIR/default/tensaku/state.toml" \
      "$HOME/.local/state/tensaku/state.toml"
  }
  build_tzupdate() {
    (cd "$1" && cargo +stable build --locked --release)
    install -m 755 "$1/target/release/tzupdate" "$HOME/.local/bin/tzupdate"
  }
  build_dua() {
    local source="$build_root/dua-cli-2.34.0"
    checkout_pinned_source https://github.com/Byron/dua-cli.git \
      19df299c07d83b6dbe48edd7e7cdf7e9d1afdc51 "$source" || return 1
    cargo +stable install --locked --path "$source" --root "$HOME/.local"
  }
  build_usage() {
    local source="$build_root/usage-5.1.0"
    checkout_pinned_source https://github.com/jdx/usage.git \
      95684d8859a31928a1871c76151dc2be4a42d0bf "$source" || return 1
    cargo +stable install --locked --path "$source/cli" --root "$HOME/.local"
  }
  build_moonlight() {
    local source="$build_root/moonlight-qt-6.1.0"
    local commit=f786e94c7b2f943e24e65d7d74deb539b827fc84
    local icon icon_dest
    if [[ ! -d $source/.git ]]; then
      git clone --filter=blob:none --no-checkout https://github.com/moonlight-stream/moonlight-qt.git "$source" || return 1
    fi
    git -C "$source" fetch --depth=1 origin "$commit" || return 1
    git -C "$source" checkout --detach "$commit" || return 1
    [[ $(git -C "$source" rev-parse HEAD) == "$commit" ]] || return 1
    git -C "$source" submodule sync --recursive || return 1
    git -C "$source" submodule update --init --recursive || return 1
    (cd "$source" && qmake6 CONFIG+=release moonlight-qt.pro && make -j"$(nproc)" release) || return 1
    install -Dm755 "$source/app/moonlight" "$HOME/.local/bin/moonlight"
    if [[ -f $source/app/deploy/linux/com.moonlight_stream.Moonlight.desktop ]]; then
      install -Dm644 "$source/app/deploy/linux/com.moonlight_stream.Moonlight.desktop" \
        "$HOME/.local/share/applications/com.moonlight_stream.Moonlight.desktop"
    else
      install_desktop moonlight Moonlight moonlight applications-games
    fi
    icon=$(find "$source/app" -type f \( -iname 'moonlight.svg' -o -iname 'moonlight.png' \) -print -quit)
    if [[ -n $icon ]]; then
      if [[ $icon == *.svg ]]; then icon_dest="$HOME/.local/share/icons/hicolor/scalable/apps/moonlight.svg";
      else icon_dest="$HOME/.local/share/icons/hicolor/512x512/apps/moonlight.png"; fi
      install -Dm644 "$icon" "$icon_dest"
    fi
  }
  build_lazydocker() {
    GOTOOLCHAIN=auto GOBIN="$HOME/.local/bin" go install \
      github.com/jesseduffield/lazydocker@v0.25.2
  }

  checkout_pinned_source() {
    local repo="$1" commit="$2" source="$3"
    if [[ ! -d $source/.git ]]; then
      git clone --filter=blob:none --no-checkout "$repo" "$source" || return 1
    fi
    git -C "$source" fetch --depth=1 origin "$commit" || return 1
    git -C "$source" checkout --detach FETCH_HEAD || return 1
    [[ $(git -C "$source" rev-parse HEAD) == "$commit" ]]
  }

  try_package_source_fallback() {
    local package="$1" binary="$2"
    shift 2
    if command -v "$binary" >/dev/null 2>&1; then
      printf 'source-skipped\t%s\t%s is already installed\n' "$package" "$binary" >>"$PACKAGE_REPORT"
      echo "$package: Debian or an existing install already provides $binary; upstream fallback skipped" \
        | tee -a "$SOURCE_BUILD_LOG"
      return 0
    fi

    echo "$package: $binary is unavailable after APT; trying its pinned upstream source" \
      | tee -a "$SOURCE_BUILD_LOG"
    printf 'source-fallback\t%s\tattempting pinned upstream source\n' "$package" >>"$PACKAGE_REPORT"
    try_build "$package" "$@"
    if command -v "$binary" >/dev/null 2>&1; then
      printf 'source-installed\t%s\t%s\n' "$package" "$binary" >>"$PACKAGE_REPORT"
      echo "$package: upstream fallback installed $binary" | tee -a "$SOURCE_BUILD_LOG"
    else
      printf 'source-failed\t%s\t%s was not produced\n' "$package" "$binary" >>"$PACKAGE_REPORT"
      warn "$package: APT did not provide $binary and its source fallback did not produce it; see $SOURCE_BUILD_LOG"
    fi
  }
  build_gpu_screen_recorder() {
    local archive="$CACHE_DIR/sources/gpu-screen-recorder-5.13.8.tar.gz"
    local checksum=62dfdf2eb1d8f700267668efede3f26cbeb424034a2ae740adbca49e064117b7
    local work="$build_root/gpu-screen-recorder-5.13.8"
    mkdir -p "${archive%/*}"
    if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null 2>&1; then
      rm -f "$archive"
      curl --proto '=https' --tlsv1.2 -fsSL \
        https://deb.debian.org/debian/pool/main/g/gpu-screen-recorder/gpu-screen-recorder_5.13.8.orig.tar.gz \
        -o "$archive" || return 1
    fi
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || return 1
    rm -rf "$work"
    mkdir -p "$work"
    tar -xzf "$archive" --strip-components=1 -C "$work" || return 1
    meson setup "$work/build" "$work" --buildtype=release --prefix="$HOME/.local" \
      -Dsystemd=false -Dcapabilities=false -Dnvidia_suspend_fix=false -Dportal=true
    meson compile -C "$work/build"
    meson install -C "$work/build"
  }
  build_tobi_try() {
    local dir="$build_root/tobi-try" commit=d1bc484cc31a34db3d287550f4800e9a6e56bacd
    local url checksum name
    mkdir -p "$dir/lib"
    for name in try.rb lib/fuzzy.rb lib/tui.rb; do
      case "$name" in
        try.rb) checksum=55a968dc5b1536b338d8f96693576c8cb19ca6bcabbca9138591cd0518486b02 ;;
        lib/fuzzy.rb) checksum=cf815ed12c8147bbc7f67008cfc1f3fd05df1638ff290e2079188f1b9bf8f190 ;;
        lib/tui.rb) checksum=b62d2b61445d8266f064e2809e06ebc0a25da401ee5a13dc3a73d215c0a1ea71 ;;
      esac
      url="https://raw.githubusercontent.com/tobi/try/$commit/$name"
      curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$dir/${name##*/}" || return 1
      printf '%s  %s\n' "$checksum" "$dir/${name##*/}" | sha256sum -c - >/dev/null || return 1
      if [[ $name == lib/* ]]; then mv "$dir/${name##*/}" "$dir/lib/${name##*/}"; fi
    done
    sed -i '1c#!/usr/bin/ruby' "$dir/try.rb"
    install -Dm755 "$dir/try.rb" "$HOME/.local/lib/tobi-try/try.rb"
    install -Dm644 "$dir/lib/fuzzy.rb" "$HOME/.local/lib/tobi-try/lib/fuzzy.rb"
    install -Dm644 "$dir/lib/tui.rb" "$HOME/.local/lib/tobi-try/lib/tui.rb"
    cat >"$HOME/.local/bin/try" <<'TRY_WRAPPER'
#!/usr/bin/env bash
exec ruby "$HOME/.local/lib/tobi-try/try.rb" "$@"
TRY_WRAPPER
    chmod 755 "$HOME/.local/bin/try"
  }
  build_sharepicker() {
    command -v rustup >/dev/null || { echo "rustup is needed for the share picker build" >&2; return 1; }
    local protocols_archive="$CACHE_DIR/sources/hyprland-protocols-3a5c2bda.tar.gz"
    local protocols_dir="$build_root/hyprland-protocols-3a5c2bda"
    local protocols_sha="00b2f15b8f383da4b6d111333c184a599ed5a9f51111243d0a88ddf7d7e498fb"
    mkdir -p "${protocols_archive%/*}"
    if [[ ! -f $protocols_archive ]] || ! printf '%s  %s\n' "$protocols_sha" "$protocols_archive" | sha256sum -c - >/dev/null 2>&1; then
      curl --proto '=https' --tlsv1.2 -fsSL \
        https://github.com/hyprwm/hyprland-protocols/archive/3a5c2bda1c1a4e55cc1330c782547695a93f05b2.tar.gz \
        -o "$protocols_archive" || return 1
    fi
    printf '%s  %s\n' "$protocols_sha" "$protocols_archive" | sha256sum -c - >/dev/null || return 1
    rm -rf "$protocols_dir"
    mkdir -p "$protocols_dir"
    tar -xzf "$protocols_archive" --strip-components=1 -C "$protocols_dir"
    rm -rf "$1/lib/hyprland-protocols"
    ln -s "$protocols_dir" "$1/lib/hyprland-protocols"
    cat >"$1/build.rs" <<'BUILD_RS'
fn main() {
    println!("cargo::rustc-env=GIT_VERSION=v0.2.1-r0-release");
}
BUILD_RS
    (cd "$1" && cargo +stable build --locked --release)
    "$1/target/release/hyprland-preview-share-picker" schema >"$1/schema.json"
    install -m 755 "$1/target/release/hyprland-preview-share-picker" "$HOME/.local/bin/hyprland-preview-share-picker"
    install -Dm644 "$1/schema.json" "$HOME/.local/share/hyprland-preview-share-picker/schema.json"
  }
  build_elsewhen() {
    local plugin="$OMARCHY_DIR/shell/plugins/omacom.elsewhen"
    grep -Eq '"id"[[:space:]]*:[[:space:]]*"omacom\.elsewhen"' "$1/manifest.json"
    mkdir -p "$plugin"
    cp -a "$1/manifest.json" "$1/cities.json" "$1/world.json" "$1/worldclock-data.py" "$plugin/"
    find "$1" -maxdepth 1 -type f \( -name '*.qml' -o -name '*.js' \) -exec cp -a {} "$plugin/" \;
  }
  build_aether() {
    local go_version node_version node_ok=0
    go_version=$(go version | awk '{print $3}' | sed 's/^go//')
    node_version=$(node --version 2>/dev/null | sed 's/^v//' || true)
    if [[ $(printf '%s\n' "$go_version" 1.25.0 | sort -V | head -n1) != 1.25.0 ]]; then
      echo "Aether: source release needs Go 1.25+; Debian's installed Go is $go_version, skipped" | tee -a "$SOURCE_BUILD_LOG"
      return 0
    fi
    if [[ $node_version == 22.* ]] && [[ $(printf '%s\n' "$node_version" 22.22.2 | sort -V | head -n1) == 22.22.2 ]]; then node_ok=1; fi
    if [[ $node_version == 24.* ]] && [[ $(printf '%s\n' "$node_version" 24.15.0 | sort -V | head -n1) == 24.15.0 ]]; then node_ok=1; fi
    if [[ $(printf '%s\n' "$node_version" 26.0.0 | sort -V | head -n1) == 26.0.0 ]]; then node_ok=1; fi
    if (( ! node_ok )); then
      echo "Aether: source release needs Node 22.22.2+, 24.15+, or 26+; Debian's installed Node is ${node_version:-missing}, skipped" | tee -a "$SOURCE_BUILD_LOG"
      return 0
    fi
    if ! command -v wails >/dev/null 2>&1; then
      GOTOOLCHAIN=auto go install github.com/wailsapp/wails/v2/cmd/wails@v2.10.2 || return 1
      export PATH="$(go env GOPATH)/bin:$PATH"
    fi
    (cd "$1" && GOTOOLCHAIN=auto make build)
    install -m 755 "$1/build/bin/aether" "$HOME/.local/bin/aether"
    install -m 644 "$1/li.oever.aether.desktop" "$HOME/.local/share/applications/"
    install -m 644 "$1/li.oever.aether.url-handler.desktop" "$HOME/.local/share/applications/"
    mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
    install -m 644 "$1/assets/aether-icon-512.png" "$HOME/.local/share/icons/hicolor/512x512/apps/aether.png"
  }
  build_owe_plugin() {
    cmake -S "$1/qml-plugin" -B "$1/qml-plugin/build" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build "$1/qml-plugin/build" --parallel "$(nproc)"
    cmake --install "$1/qml-plugin/build"
  }

  try_build asdcontrol build_archive asdcontrol 0.6.0 omakasui/asdcontrol \
    3112a6d5fc51a204c96ef9d27187577c6efc80b952e37a77969efbd0124e81d3 build_asdcontrol
  try_build cliamp build_archive cliamp 2.2.0 bjarneo/cliamp \
    54ffbba6983880c915d2c13c83ca1339de2d2a3c5af3bb0a176923faa9afc015 build_cliamp
  try_build herdr build_archive herdr 0.9.1 herdrdev/herdr \
    03403d3ef80dcf2b954dd5d27eb636e6c4f5279d240b48de272b7f53e4b73093 build_herdr
  try_build omacalc build_archive omacalc 0.2.2 omacom-io/omacalc \
    a42b39cd5a62c83f6667060da19c9bcc5dd8469ce69e48f19394b71322b9cba4 build_omacalc
  try_build omacut build_archive omacut 0.4.0 omacom-io/omacut \
    0e1b0665e0304a1ecbdb06b8574e8abf385e1cffa431821032902340c2c5d7df build_omacut
  try_build omawrite build_archive omawrite 0.5.0 omacom/omawrite \
    b57e418212f9bde0b8a12cff2424a43f15829a56a58fdc49542a0393a430f938 build_omawrite
  try_build omasnap build_archive omasnap 1.21.0 omacom/omasnap \
    2f842edf67631825fa1e102876020040ea3e21341221a428b6aeee5580a9d928 build_omasnap
  try_build owe build_archive owe 0.2.6 omacom/owe \
    e5c10e60bdfaebed861a3b7515c691a5a78fc0fe3ab29c0e96d934eb1a957cf8 build_owe
  try_build ttfx build_archive ttfx 0.3.3 omacom-io/ttfx \
    d040da0da2f4a952a367fa3d934ac25999265405f1d2a9f0475625e41211fa7d build_ttfx
  try_build tensaku build_archive tensaku 0.29.0 jondkinney/tensaku \
    31595a8b4600107a63c1e5889f50f40e1ef832e51cfc038c1a7750b987fd34d0 build_tensaku
  try_package_source_fallback dua-cli dua build_dua
  try_package_source_fallback usage usage build_usage
  try_package_source_fallback lazydocker lazydocker build_lazydocker
  try_package_source_fallback gpu-screen-recorder-cli gpu-screen-recorder build_gpu_screen_recorder
  try_package_source_fallback moonlight-qt moonlight build_moonlight
  try_package_source_fallback tobi-try try build_tobi_try
  try_build tzupdate build_archive tzupdate 3.1.0 cdown/tzupdate \
    aebf678afd261852bd3ebf4689a9a7382c3e4e43a92864b77cbee2d26ec62e22 build_tzupdate ''
  try_build elsewhen build_archive elsewhen 1.0.0 omacom/elsewhen \
    3124f0c0a19ebc1b158bcf04151cddd6c733ceeead88052186b6a54c46bee263 build_elsewhen
  try_build hyprland-preview-share-picker build_archive hyprland-preview-share-picker 0.2.1 WhySoBad/hyprland-preview-share-picker \
    dfbd6773884c24bb300d756420cc540dda0c3518e910e20d1538e7dd6c0990da build_sharepicker
  try_build aether build_archive aether 4.30.0 omacom/aether \
    f67c8d2c6f27f67a755bc279ece5ddb194f1bb165648280b9a7be86904d36ff5 build_aether
  try_build owe-lockfeed build_archive owe 0.2.6 omacom/owe \
    e5c10e60bdfaebed861a3b7515c691a5a78fc0fe3ab29c0e96d934eb1a957cf8 build_owe_plugin
}

if [[ $SOURCE_BUILDS == 1 ]]; then
  say "Building Omarchy companion applications and missing-package source fallbacks"
  : >"$SOURCE_BUILD_LOG"
  build_source_extras || warn "Some optional source builds did not complete; see $SOURCE_BUILD_LOG"
  if [[ ! -x $HOME/.local/bin/hyprland-preview-share-picker && -f $HOME/.config/hypr/xdph.conf ]]; then
    sed -i '/custom_picker_binary[[:space:]]*=/d' "$HOME/.config/hypr/xdph.conf"
  fi
else
  say "Skipping optional source builds (--skip-source-builds)"
fi

install_omarchy_system_payload() {
  local root=/usr/share/omarchy marker=/usr/share/omarchy/.omarchy-debian-release
  local source_path base relative staging

  if sudo test -d "$root" && ! sudo test -f "$marker"; then
    die "$root already exists without this installer's ownership marker; refusing to replace it."
  fi

  # Detect unrelated command collisions before installing any upstream runtime
  # scripts into Debian's /usr/bin namespace.
  if ! sudo test -f "$marker"; then
    for source_path in "$OMARCHY_DIR"/bin/*; do
      [[ -f $source_path ]] || continue
      base=${source_path##*/}
      case "$base" in omarchy-debug|omarchy-debug-idle|omarchy-upload-log) continue ;; esac
      if sudo test -e "/usr/bin/$base" && ! sudo cmp -s "$source_path" "/usr/bin/$base"; then
        die "Refusing to replace existing /usr/bin/$base; move it aside and rerun if it is safe to replace."
      fi
    done
  fi

  sudo install -d -m 0755 "$root"
  sudo tee "$marker" >/dev/null <<EOF_MARKER
Omarchy $OMARCHY_TAG ($OMARCHY_COMMIT), installed by install-omarchy-debian.sh
EOF_MARKER

  # Match Omarchy's package-owned filesystem layout so its absolute paths,
  # UWSM environment, service units, and refresh commands resolve as designed.
  for relative in default install themes migrations shell config applications; do
    [[ -d $OMARCHY_DIR/$relative ]] || continue
    sudo install -d -m 0755 "$root/$relative"
    sudo cp -a "$OMARCHY_DIR/$relative/." "$root/$relative/"
  done
  sudo rm -f "$root/config/autostart/limine-snapper-notify.desktop"
  sudo install -m 0644 "$OMARCHY_DIR/version" "$root/version"
  if ! sudo test -e /etc/fastfetch/config.jsonc; then
    sudo install -Dm0644 "$OMARCHY_DIR/etc/fastfetch/config.jsonc" /etc/fastfetch/config.jsonc
  fi

  sudo install -d -m 0755 "$root/bin"
  for source_path in "$OMARCHY_DIR"/bin/*; do
    [[ -f $source_path ]] || continue
    base=${source_path##*/}
    case "$base" in omarchy-debug|omarchy-debug-idle|omarchy-upload-log) continue ;; esac
    sudo install -m 0755 "$source_path" "/usr/bin/$base"
    sudo ln -sfn "/usr/bin/$base" "$root/bin/$base"
  done

  sudo install -Dm0644 "$OMARCHY_DIR/default/uwsm/env.d/10-omarchy" \
    /usr/share/uwsm/env.d/10-omarchy
  sudo install -Dm0644 "$OMARCHY_DIR/default/environment.d/10-omarchy-fcitx.conf" \
    /usr/lib/environment.d/10-omarchy-fcitx.conf
  sudo install -Dm0644 "$OMARCHY_DIR/default/fontconfig/conf.avail/50-omarchy.conf" \
    /usr/share/fontconfig/conf.avail/50-omarchy.conf
  if ! sudo test -e /etc/fonts/conf.d/50-omarchy.conf; then
    sudo ln -s /usr/share/fontconfig/conf.avail/50-omarchy.conf /etc/fonts/conf.d/50-omarchy.conf
  fi
  sudo install -Dm0644 "$OMARCHY_DIR/default/xdg-terminal-exec/hyprland-xdg-terminals.list" \
    /usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list
  sudo install -Dm0644 "$OMARCHY_DIR/default/applications/mimeapps.list" \
    /usr/share/applications/mimeapps.list

  sudo install -d -m 0755 /usr/lib/systemd/user
  for source_path in "$OMARCHY_DIR"/default/systemd/user/*.service; do
    [[ -f $source_path ]] || continue
    sudo install -m 0644 "$source_path" "/usr/lib/systemd/user/${source_path##*/}"
  done
  sudo install -Dm0644 "$OMARCHY_DIR/default/systemd/user/app.slice.d/10-oomd.conf" \
    /usr/lib/systemd/user/app.slice.d/10-oomd.conf
  sudo install -Dm0644 "$OMARCHY_DIR/etc/systemd/oomd.conf.d/10-omarchy.conf" \
    /usr/lib/systemd/oomd.conf.d/10-omarchy.conf
  sudo install -Dm0644 "$OMARCHY_DIR/etc/systemd/system.conf.d/20-omarchy-nofile.conf" \
    /usr/lib/systemd/system.conf.d/20-omarchy-nofile.conf
  sudo install -Dm0644 "$OMARCHY_DIR/etc/systemd/user.conf.d/20-omarchy-nofile.conf" \
    /usr/lib/systemd/user.conf.d/20-omarchy-nofile.conf
  sudo install -Dm0644 "$OMARCHY_DIR/default/systemd/zram-generator.conf.d/90-omarchy.conf" \
    /usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf
  sudo install -Dm0755 "$OMARCHY_DIR/default/systemd/system-sleep/unmount-fuse" \
    /usr/lib/systemd/system-sleep/unmount-fuse

  sudo install -d -m 0755 /usr/share/sddm/themes/omarchy
  sudo cp -an "$OMARCHY_DIR/default/sddm/omarchy/." /usr/share/sddm/themes/omarchy/
  sudo find /usr/share/sddm/themes/omarchy -type d -exec chmod 0755 {} +
  sudo find /usr/share/sddm/themes/omarchy -type f -exec chmod 0644 {} +
  sudo chown -R root:root /usr/share/sddm/themes/omarchy
  sudo install -Dm0644 "$OMARCHY_DIR/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua
  sudo install -Dm0644 "$OMARCHY_DIR/default/fonts/omarchy/omarchy.ttf" \
    /usr/share/fonts/omarchy/omarchy.ttf
  sudo install -Dm0644 "$OMARCHY_DIR/logo.txt" /usr/share/omarchy/logo.txt
  sudo install -Dm0644 "$OMARCHY_DIR/logo.svg" /usr/share/omarchy/logo.svg
  sudo install -Dm0644 "$OMARCHY_DIR/icon.txt" /usr/share/omarchy/icon.txt
  sudo install -Dm0644 "$OMARCHY_DIR/icon.png" /usr/share/omarchy/icon.png
  sudo install -Dm0644 "$OMARCHY_DIR/icon.png" /usr/share/pixmaps/omarchy.png
  sudo install -Dm0644 "$OMARCHY_DIR/icon.png" /usr/share/icons/hicolor/256x256/apps/omarchy.png
  sudo install -d -m 0755 /usr/share/plymouth/themes/omarchy
  sudo cp -a "$OMARCHY_DIR/default/plymouth/." /usr/share/plymouth/themes/omarchy/
  sudo find /usr/share/plymouth/themes/omarchy -type d -exec chmod 0755 {} +
  sudo find /usr/share/plymouth/themes/omarchy -type f -exec chmod 0644 {} +
  sudo chown -R root:root /usr/share/plymouth/themes/omarchy

  # Put Omarchy's defaults in the template used for future accounts, but do not
  # overwrite any files an administrator has already placed in /etc/skel.
  staging="$CACHE_DIR/skel-config"
  rm -rf "$staging"
  mkdir -p "$staging"
  cp -a "$OMARCHY_DIR/config/." "$staging/"
  rm -f "$staging/autostart/limine-snapper-notify.desktop"
  install -Dm0644 "$OMARCHY_DIR/default/hypr/toggles/flags.lua" \
    "$staging/.local/state/omarchy/toggles/hypr/flags.lua"
  install -Dm0644 "$OMARCHY_DIR/default/nautilus-python/extensions/localsend.py" \
    "$staging/.local/share/nautilus-python/extensions/localsend.py"
  install -Dm0644 "$OMARCHY_DIR/default/nautilus-python/extensions/transcode.py" \
    "$staging/.local/share/nautilus-python/extensions/transcode.py"
  install -Dm0644 "$OMARCHY_DIR/logo.txt" "$staging/.config/omarchy/branding/screensaver.txt"
  install -Dm0644 "$OMARCHY_DIR/icon.txt" "$staging/.config/omarchy/branding/about.txt"
  printf '# Generated by Omarchy on Debian\ninclude "/usr/share/omarchy/default/xcompose"\n' >"$staging/.XCompose"
  if [[ -d $HOME/.config/nvim ]]; then cp -a "$HOME/.config/nvim" "$staging/.config/nvim"; fi
  sudo install -d -m 0755 /etc/skel/.config
  sudo install -d -m 0755 /etc/skel/.local
  sudo cp -Rn "$staging/." /etc/skel/
  sudo chown -R root:root "$root"

  sudo install -Dm0644 /dev/stdin /etc/profile.d/omarchy-debian.sh <<'PROFILE'
# Omarchy's Debian session environment (system files installed by the Debian adapter).
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap
PROFILE

  if sudo test -d /etc/sddm.conf.d; then
    if ! sudo test -e /etc/sddm.conf.d/90-omarchy-debian.conf || \
      sudo grep -q '^# Managed by install-omarchy-debian.sh$' /etc/sddm.conf.d/90-omarchy-debian.conf; then
      sudo tee /etc/sddm.conf.d/90-omarchy-debian.conf >/dev/null <<'SDDM'
# Managed by install-omarchy-debian.sh
[Theme]
Current=omarchy

[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua
SDDM
    else
      warn "Preserving existing /etc/sddm.conf.d/90-omarchy-debian.conf"
    fi
  fi

  # Keep newly-created interactive users on Omarchy's Bash defaults while
  # retaining Debian's existing skeleton setup and administrator additions.
  if ! sudo grep -q 'OMARCHY_DEBIAN_SETUP' /etc/skel/.bashrc; then
    sudo tee -a /etc/skel/.bashrc >/dev/null <<'SKEL_BASHRC'

# OMARCHY_DEBIAN_SETUP
[[ -r /usr/share/omarchy/default/bashrc ]] && source /usr/share/omarchy/default/bashrc
SKEL_BASHRC
  fi

  command -v fc-cache >/dev/null 2>&1 && sudo fc-cache -f /usr/share/fonts/omarchy >/dev/null 2>&1 || true
}

say "Installing Omarchy's system runtime, login theme, session environment, and defaults"
install_omarchy_system_payload

say "Applying Omarchy's first-user defaults and enabling its user services"
OMARCHY_PATH=/usr/share/omarchy \
  PATH="/usr/share/omarchy/bin:$HOME/.local/bin:$PATH" \
  OMARCHY_THEME_HEADLESS=1 omarchy-provision-first-run || \
  warn "Omarchy first-user setup did not finish; run omarchy-provision-first-run after logging in."

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi
if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true; fi

say "Omarchy on Debian is installed"
cat <<EOF
Log out, select “Omarchy on Debian” from the login-session menu, then log in.

Upstream user configuration: $HOME/.config
Omarchy source and themes:   $OMARCHY_DIR
Build log:                   $SOURCE_BUILD_LOG
Package report:              $PACKAGE_REPORT

Package updates use Debian: run “omarchy update” or “sudo apt full-upgrade”.
This installer leaves the machine running; reboot when convenient.
EOF
