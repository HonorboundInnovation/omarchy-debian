#!/usr/bin/env bash
# Install the missing Omarchy 4.0.4 components on Debian 13.
# Run as a regular Debian 13 user. Build products go in ~/.local; Debian packages
# and the two pinned upstream binaries use sudo where system installation is needed.

set -Eeuo pipefail
umask 022

readonly CACHE="$HOME/.cache/omarchy-debian/missing-components"
readonly BUILD="$CACHE/build"
readonly DOWNLOADS="$CACHE/downloads"
readonly LOG_DIR="$CACHE/logs"
ARCH=$(dpkg --print-architecture)
readonly ARCH
export PATH="$HOME/.local/bin:$PATH"

components=(
  lazydocker dua-cli localsend mise obsidian moonlight-qt usage tobi-try
  fonts-ia-writer ufw-docker gpu-screen-recorder-cli inetutils nss-mdns
  pinta nautilus-python sushi docker-compose-v2
  aether asdcontrol cliamp herdr hyprland-preview-share-picker
  omacalc omacut omawrite tensaku ttfx tzupdate dotnet-runtime pipewire-jack
)

show_usage() {
  cat <<'EOF'
Usage: ./install-omarchy-debian-missing.sh [--only COMPONENT | --list]

Install the original 17 skipped components plus Omarchy companion apps and
runtime gaps. Existing components are skipped. Source builds and fonts install
under ~/.local.
Pinta uses its official Flatpak; Obsidian and LocalSend use upstream packages.
The .NET runtime adds Microsoft's Debian 13 APT feed if needed.
This script does not replace Debian's kernel or change filesystems/bootloaders.
Results and detailed logs are saved under ~/.cache/omarchy-debian/missing-components.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
installed_pkg() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'
}
has_bin() { command -v "$1" >/dev/null 2>&1; }
apt_install() { sudo apt-get install -y -- "$@"; }
verify_sha256() { printf '%s  %s\n' "$2" "$1" | sha256sum -c -; }

fetch_verified() {
  local url="$1" output="$2" sha="$3"
  mkdir -p "${output%/*}"
  if [[ ! -f $output ]] || ! verify_sha256 "$output" "$sha" >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 "$url" -o "$output.tmp"
    verify_sha256 "$output.tmp" "$sha"
    mv -f "$output.tmp" "$output"
  fi
  verify_sha256 "$output" "$sha"
}

checkout_commit() {
  local url="$1" commit="$2" target="$3"
  if [[ ! -d $target/.git ]]; then
    git clone --filter=blob:none --no-checkout "$url" "$target"
  fi
  git -C "$target" fetch --depth=1 origin "$commit"
  git -C "$target" checkout --detach FETCH_HEAD
  [[ $(git -C "$target" rev-parse HEAD) == "$commit" ]]
}

build_archive() {
  local name="$1" version="$2" repo="$3" sha="$4" builder="$5" tag_prefix="${6-v}"
  local archive="$DOWNLOADS/$name-$version.tar.gz" work="$BUILD/$name-$version"
  fetch_verified "https://github.com/$repo/archive/refs/tags/$tag_prefix$version.tar.gz" "$archive" "$sha"
  rm -rf -- "$work"
  mkdir -p "$work"
  tar -xzf "$archive" --strip-components=1 -C "$work"
  "$builder" "$work"
}

install_desktop() {
  local name="$1" title="$2" command_name="$3" icon="$4"
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/$name.desktop" <<EOF
[Desktop Entry]
Name=$title
Exec=$command_name
Icon=$icon
Terminal=false
Type=Application
Categories=Utility;
EOF
}

install_rust_build_tools() {
  apt_install rustup git build-essential pkgconf libssl-dev
  rustup toolchain install stable --profile minimal
}

install_lazydocker() {
  has_bin lazydocker && return 0
  apt_install golang-go git ca-certificates
  GOTOOLCHAIN=auto GOBIN="$HOME/.local/bin" go install github.com/jesseduffield/lazydocker@v0.25.2
  has_bin lazydocker
}

install_dua_cli() {
  has_bin dua && return 0
  apt_install rustup git build-essential pkgconf libssl-dev
  rustup toolchain install stable --profile minimal
  local source="$BUILD/dua-cli"
  checkout_commit https://github.com/Byron/dua-cli.git \
    19df299c07d83b6dbe48edd7e7cdf7e9d1afdc51 "$source"
  cargo +stable install --locked --path "$source" --root "$HOME/.local"
  has_bin dua
}

install_localsend() {
  installed_pkg localsend && return 0
  local url sha archive="$DOWNLOADS/localsend-1.18.2-$ARCH.deb"
  case "$ARCH" in
    amd64)
      url=https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-x86-64.deb
      sha=cc42a4f3eacdcb25ec31f0016b1272acb003145ab30484db8965450e20c72cd2 ;;
    arm64)
      url=https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-arm-64.deb
      sha=bbd8347b7979f936d3bae176a3f0d9b81431605707c585270d6240f7670feb1f ;;
    *) die "LocalSend's pinned .deb is unavailable for $ARCH" ;;
  esac
  fetch_verified "$url" "$archive" "$sha"
  [[ $(dpkg-deb -f "$archive" Package) == localsend ]] || die 'Unexpected LocalSend package name'
  apt_install "$archive"
  installed_pkg localsend
}

install_mise() {
  has_bin mise && return 0
  local version=2026.9.12 suffix sha archive unpack binary
  case "$ARCH" in
    amd64) suffix=x64; sha=30c79a0a24d8f0ad80e6c9b11ec54816be2a9b77e7eeae32c1267a5b9d34d3d7 ;;
    arm64) suffix=arm64; sha=7bc2a5558b787a33f22e4b5955cfec58871ad3723658418ad3d2cdf5a0e693b9 ;;
    *) die "Mise's pinned binary is unavailable for $ARCH" ;;
  esac
  archive="$DOWNLOADS/mise-v$version-linux-$suffix.tar.xz"
  unpack="$BUILD/mise-v$version-linux-$suffix"
  fetch_verified "https://github.com/jdx/mise/releases/download/v$version/mise-v$version-linux-$suffix.tar.xz" "$archive" "$sha"
  mkdir -p "$unpack"
  tar -xJf "$archive" -C "$unpack"
  binary=$(find "$unpack" -type f -path '*/bin/mise' -print -quit)
  [[ -n $binary ]] || die 'Mise binary missing from verified archive'
  sudo install -Dm0755 "$binary" /usr/local/bin/mise
  has_bin mise
}

install_obsidian() {
  installed_pkg obsidian && return 0
  [[ $ARCH == amd64 ]] || die "Obsidian's official .deb is only offered for amd64; see https://obsidian.md/download"
  local page="$DOWNLOADS/obsidian-download.html" url archive
  curl --proto '=https' --tlsv1.2 -fL --retry 3 https://obsidian.md/download -o "$page"
  url=$(python3 - "$page" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import re
import sys

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.urls.extend(value for key, value in attrs if key == 'href' and value)

parser = Links()
parser.feed(Path(sys.argv[1]).read_text())
pattern = re.compile(r'^https://github\.com/obsidianmd/obsidian-releases/releases/download/v[0-9][^/]+/obsidian_[0-9][^/]+_amd64\.deb$')
matches = [url for url in parser.urls if pattern.fullmatch(url)]
if len(matches) != 1:
    raise SystemExit('Could not identify one official Obsidian amd64 .deb link')
print(matches[0])
PY
  )
  archive="$DOWNLOADS/${url##*/}"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 "$url" -o "$archive.tmp"
  [[ $(dpkg-deb -f "$archive.tmp" Package) == obsidian ]] || die 'Unexpected Obsidian package name'
  mv -f "$archive.tmp" "$archive"
  apt_install "$archive"
  installed_pkg obsidian
}

install_moonlight_qt() {
  has_bin moonlight && return 0
  apt_install git build-essential pkgconf qt6-base-dev qt6-multimedia-dev qt6-svg-dev \
    qt6-declarative-dev libssl-dev libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev libopus-dev libvpx-dev libwayland-dev libsdl2-dev \
    libxkbcommon-dev/trixie-backports
  has_bin qmake6 || die 'qmake6 is required for Moonlight Qt'
  local source="$BUILD/moonlight-qt" icon
  checkout_commit https://github.com/moonlight-stream/moonlight-qt.git \
    f786e94c7b2f943e24e65d7d74deb539b827fc84 "$source"
  git -C "$source" submodule sync --recursive
  git -C "$source" submodule update --init --recursive
  (cd "$source" && qmake6 CONFIG+=release moonlight-qt.pro && make -j"$(nproc)" release)
  install -Dm0755 "$source/app/moonlight" "$HOME/.local/bin/moonlight"
  if [[ -f $source/app/deploy/linux/com.moonlight_stream.Moonlight.desktop ]]; then
    install -Dm0644 "$source/app/deploy/linux/com.moonlight_stream.Moonlight.desktop" \
      "$HOME/.local/share/applications/com.moonlight_stream.Moonlight.desktop"
  fi
  icon=$(find "$source/app" -type f \( -iname 'moonlight.svg' -o -iname 'moonlight.png' \) -print -quit)
  if [[ -n $icon ]]; then
    install -Dm0644 "$icon" "$HOME/.local/share/icons/hicolor/$(basename "$icon")"
  fi
  has_bin moonlight
}

install_usage() {
  has_bin usage && return 0
  apt_install rustup git build-essential pkgconf libssl-dev
  rustup toolchain install stable --profile minimal
  local source="$BUILD/usage"
  checkout_commit https://github.com/jdx/usage.git \
    95684d8859a31928a1871c76151dc2be4a42d0bf "$source"
  cargo +stable install --locked --path "$source/cli" --root "$HOME/.local"
  has_bin usage
}

install_tobi_try() {
  has_bin try && return 0
  apt_install git ruby
  local source="$BUILD/tobi-try"
  checkout_commit https://github.com/tobi/try.git \
    d1bc484cc31a34db3d287550f4800e9a6e56bacd "$source"
  install -Dm0755 "$source/try.rb" "$HOME/.local/lib/tobi-try/try.rb"
  install -Dm0644 "$source/lib/fuzzy.rb" "$HOME/.local/lib/tobi-try/lib/fuzzy.rb"
  install -Dm0644 "$source/lib/tui.rb" "$HOME/.local/lib/tobi-try/lib/tui.rb"
  cat >"$HOME/.local/bin/try" <<'WRAPPER'
#!/usr/bin/env bash
exec ruby "$HOME/.local/lib/tobi-try/try.rb" "$@"
WRAPPER
  chmod 0755 "$HOME/.local/bin/try"
  has_bin try
}

install_fonts_ia_writer() {
  if fc-list 2>/dev/null | grep -i 'iA Writer' >/dev/null; then return 0; fi
  apt_install git fontconfig
  local source="$BUILD/iA-Fonts" target="$HOME/.local/share/fonts/iA-Writer" count=0 font
  if [[ ! -d $source/.git ]]; then
    git clone --depth=1 https://github.com/iaolo/iA-Fonts.git "$source"
  fi
  mkdir -p "$target"
  while IFS= read -r -d '' font; do
    install -m0644 "$font" "$target/$(basename "$font")"
    ((count += 1))
  done < <(find "$source" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
  ((count > 0)) || die 'No installable iA Writer font files found'
  fc-cache -f "$target"
  fc-list | grep -i 'iA Writer' >/dev/null
}

install_ufw_docker() {
  has_bin ufw-docker && return 0
  local archive="$DOWNLOADS/ufw-docker-251123.tar.gz" work="$BUILD/ufw-docker"
  local checksum=d4ac771a83a5f7bd328c8d30094a45752dd1b38de7f2d7f5269e369289d9e8ef189b020b97e4d93025d9d7ad61757cda31f80e548e8611b77653f75e731400b7
  if [[ ! -f $archive ]] || ! printf '%s  %s\n' "$checksum" "$archive" | b2sum -c - >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
      https://github.com/chaifeng/ufw-docker/archive/refs/tags/251123.tar.gz -o "$archive.tmp"
    printf '%s  %s\n' "$checksum" "$archive.tmp" | b2sum -c -
    mv -f "$archive.tmp" "$archive"
  fi
  rm -rf -- "$work"
  mkdir -p "$work"
  tar -xzf "$archive" --strip-components=1 -C "$work"
  sudo install -Dm0755 "$work/ufw-docker" /usr/local/bin/ufw-docker
  has_bin ufw-docker
}

install_gpu_screen_recorder_cli() {
  has_bin gpu-screen-recorder && return 0
  apt_install build-essential pkgconf meson ninja-build libx11-dev libxcomposite-dev \
    libxrandr-dev libxfixes-dev libxdamage-dev libwayland-dev libva-dev libpulse-dev \
    libdrm-dev libcap-dev libdbus-1-dev libvulkan-dev libavcodec-dev \
    libavformat-dev libavutil-dev libswresample-dev libavfilter-dev libpipewire-0.3-dev
  local archive="$DOWNLOADS/gpu-screen-recorder-5.13.8.tar.gz" work="$BUILD/gpu-screen-recorder"
  fetch_verified \
    https://deb.debian.org/debian/pool/main/g/gpu-screen-recorder/gpu-screen-recorder_5.13.8.orig.tar.gz \
    "$archive" 62dfdf2eb1d8f700267668efede3f26cbeb424034a2ae740adbca49e064117b7
  rm -rf -- "$work"
  mkdir -p "$work"
  tar -xzf "$archive" --strip-components=1 -C "$work"
  meson setup "$work/build" "$work" --buildtype=release --prefix="$HOME/.local" \
    -Dsystemd=false -Dcapabilities=false -Dnvidia_suspend_fix=false -Dportal=true
  meson compile -C "$work/build"
  meson install -C "$work/build"
  has_bin gpu-screen-recorder
}

install_inetutils() { installed_pkg inetutils-telnet || apt_install inetutils-telnet; }
install_nss_mdns() { installed_pkg libnss-mdns || apt_install libnss-mdns; }
install_nautilus_python() { installed_pkg python3-nautilus || apt_install python3-nautilus; }
install_sushi() { installed_pkg gnome-sushi || apt_install gnome-sushi; }
install_docker_compose_v2() { installed_pkg docker-compose || apt_install docker-compose; }

install_pinta() {
  if has_bin pinta || flatpak info --user com.github.PintaProject.Pinta >/dev/null 2>&1; then return 0; fi
  apt_install flatpak
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install --user --noninteractive -y flathub com.github.PintaProject.Pinta
  flatpak info --user com.github.PintaProject.Pinta >/dev/null
}

build_asdcontrol() {
  (cd "$1" && make)
  install -Dm0755 "$1/asdcontrol" "$HOME/.local/bin/asdcontrol"
}
install_asdcontrol() {
  has_bin asdcontrol && return 0
  apt_install build-essential libasound2-dev
  build_archive asdcontrol 0.6.0 omakasui/asdcontrol \
    3112a6d5fc51a204c96ef9d27187577c6efc80b952e37a77969efbd0124e81d3 build_asdcontrol
  has_bin asdcontrol
}

build_cliamp() {
  (cd "$1" && GOTOOLCHAIN=auto go build -trimpath -buildmode=pie -ldflags='-s -w' \
    -o "$HOME/.local/bin/cliamp" .)
}
install_cliamp() {
  has_bin cliamp && return 0
  apt_install golang-go git build-essential
  build_archive cliamp 2.2.0 bjarneo/cliamp \
    54ffbba6983880c915d2c13c83ca1339de2d2a3c5af3bb0a176923faa9afc015 build_cliamp
  has_bin cliamp
}

build_herdr() {
  local zig_arch zig_sha zig_version=0.16.0 zig_archive zig_dir
  case "$ARCH" in
    amd64) zig_arch=x86_64; zig_sha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
    arm64) zig_arch=aarch64; zig_sha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;;
    *) die "Herdr's pinned Zig toolchain is unavailable for $ARCH" ;;
  esac
  zig_archive="$DOWNLOADS/zig-$zig_arch-linux-$zig_version.tar.xz"
  zig_dir="$BUILD/zig-$zig_arch-linux-$zig_version"
  fetch_verified "https://ziglang.org/download/$zig_version/zig-$zig_arch-linux-$zig_version.tar.xz" \
    "$zig_archive" "$zig_sha"
  rm -rf -- "$zig_dir"
  tar -xJf "$zig_archive" -C "$BUILD"
  (cd "$1" && ZIG="$zig_dir/zig" ZIG_GLOBAL_CACHE_DIR="$BUILD/zig-cache" \
    cargo +stable build --locked --release)
  install -Dm0755 "$1/target/release/herdr" "$HOME/.local/bin/herdr"
}
install_herdr() {
  has_bin herdr && return 0
  install_rust_build_tools
  build_archive herdr 0.9.1 herdrdev/herdr \
    03403d3ef80dcf2b954dd5d27eb636e6c4f5279d240b48de272b7f53e4b73093 build_herdr
  has_bin herdr
}

install_oma_build_deps() {
  apt_install build-essential clang cmake ninja-build meson pkgconf \
    libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev libmpv-dev \
    libasound2-dev libflac-dev libvorbis-dev libogg-dev libmpg123-dev \
    libtesseract-dev libglib2.0-dev libepoxy-dev libfontconfig1-dev \
    libxkbcommon-dev/trixie-backports
}
build_omacalc() {
  (cd "$1" && ./bin/build)
  install -Dm0755 "$1/build/omacalc" "$HOME/.local/bin/omacalc"
  install_desktop omacalc OmaCalc omacalc accessories-calculator
}
install_omacalc() {
  has_bin omacalc && return 0
  install_oma_build_deps
  build_archive omacalc 0.2.2 omacom-io/omacalc \
    a42b39cd5a62c83f6667060da19c9bcc5dd8469ce69e48f19394b71322b9cba4 build_omacalc
  has_bin omacalc
}
build_omacut() {
  (cd "$1" && ./bin/build)
  install -Dm0755 "$1/build/omacut" "$HOME/.local/bin/omacut"
  install_desktop omacut OmaCut omacut applications-multimedia
}
install_omacut() {
  has_bin omacut && return 0
  install_oma_build_deps
  build_archive omacut 0.4.0 omacom-io/omacut \
    0e1b0665e0304a1ecbdb06b8574e8abf385e1cffa431821032902340c2c5d7df build_omacut
  has_bin omacut
}
build_omawrite() {
  (cd "$1" && ./bin/build)
  install -Dm0755 "$1/build/omawrite" "$HOME/.local/bin/omawrite"
  install_desktop omawrite OmaWrite omawrite accessories-text-editor
}
install_omawrite() {
  has_bin omawrite && return 0
  install_oma_build_deps
  build_archive omawrite 0.5.0 omacom/omawrite \
    b57e418212f9bde0b8a12cff2424a43f15829a56a58fdc49542a0393a430f938 build_omawrite
  has_bin omawrite
}

build_ttfx() {
  (cd "$1" && cargo +stable build --locked --release)
  install -Dm0755 "$1/target/release/ttfx" "$HOME/.local/bin/ttfx"
}
install_ttfx() {
  has_bin ttfx && return 0
  install_rust_build_tools
  apt_install libfontconfig1-dev
  build_archive ttfx 0.3.3 omacom-io/ttfx \
    d040da0da2f4a952a367fa3d934ac25999265405f1d2a9f0475625e41211fa7d build_ttfx
  has_bin ttfx
}

build_tensaku() {
  (cd "$1" && cargo +stable build --locked --release --features ci-release)
  install -Dm0755 "$1/target/release/tensaku" "$HOME/.local/bin/tensaku"
  install -Dm0755 "$1/assets/tensaku-edit" "$HOME/.local/bin/tensaku-edit"
  install -Dm0644 "$1/dev.tensaku.Tensaku.desktop" \
    "$HOME/.local/share/applications/dev.tensaku.Tensaku.desktop"
  install -Dm0644 "$1/assets/tensaku.svg" \
    "$HOME/.local/share/icons/hicolor/scalable/apps/dev.tensaku.Tensaku.svg"
  if [[ -f /usr/share/omarchy/default/tensaku/state.toml && \
        ! -e $HOME/.local/state/tensaku/state.toml ]]; then
    install -Dm0644 /usr/share/omarchy/default/tensaku/state.toml \
      "$HOME/.local/state/tensaku/state.toml"
  fi
}
install_tensaku() {
  has_bin tensaku && return 0
  install_rust_build_tools
  apt_install libgtk-4-dev libadwaita-1-dev libglib2.0-dev \
    libxkbcommon-dev/trixie-backports
  build_archive tensaku 0.29.0 jondkinney/tensaku \
    31595a8b4600107a63c1e5889f50f40e1ef832e51cfc038c1a7750b987fd34d0 build_tensaku
  has_bin tensaku
}

build_tzupdate() {
  (cd "$1" && cargo +stable build --locked --release)
  install -Dm0755 "$1/target/release/tzupdate" "$HOME/.local/bin/tzupdate"
}
install_tzupdate() {
  has_bin tzupdate && return 0
  install_rust_build_tools
  build_archive tzupdate 3.1.0 cdown/tzupdate \
    aebf678afd261852bd3ebf4689a9a7382c3e4e43a92864b77cbee2d26ec62e22 build_tzupdate ''
  has_bin tzupdate
}

build_share_picker() {
  local archive="$DOWNLOADS/hyprland-protocols-3a5c2bda.tar.gz"
  local protocols="$BUILD/hyprland-protocols-3a5c2bda"
  fetch_verified \
    https://github.com/hyprwm/hyprland-protocols/archive/3a5c2bda1c1a4e55cc1330c782547695a93f05b2.tar.gz \
    "$archive" 00b2f15b8f383da4b6d111333c184a599ed5a9f51111243d0a88ddf7d7e498fb
  rm -rf -- "$protocols" "$1/lib/hyprland-protocols"
  mkdir -p "$protocols"
  tar -xzf "$archive" --strip-components=1 -C "$protocols"
  ln -s "$protocols" "$1/lib/hyprland-protocols"
  cat >"$1/build.rs" <<'BUILD_RS'
fn main() {
    println!("cargo::rustc-env=GIT_VERSION=v0.2.1-r0-release");
}
BUILD_RS
  (cd "$1" && cargo +stable build --locked --release)
  "$1/target/release/hyprland-preview-share-picker" schema >"$1/schema.json"
  install -Dm0755 "$1/target/release/hyprland-preview-share-picker" \
    "$HOME/.local/bin/hyprland-preview-share-picker"
  install -Dm0644 "$1/schema.json" \
    "$HOME/.local/share/hyprland-preview-share-picker/schema.json"
}
install_hyprland_preview_share_picker() {
  has_bin hyprland-preview-share-picker && return 0
  install_rust_build_tools
  apt_install libwayland-dev wayland-protocols libxkbcommon-dev/trixie-backports pkgconf
  build_archive hyprland-preview-share-picker 0.2.1 WhySoBad/hyprland-preview-share-picker \
    dfbd6773884c24bb300d756420cc540dda0c3518e910e20d1538e7dd6c0990da build_share_picker
  has_bin hyprland-preview-share-picker
}

build_aether() {
  local source="$1" go_bin
  go_bin=$(mise exec go@1.25 node@24.15.0 -- go env GOPATH)
  mise exec go@1.25 node@24.15.0 -- bash -c '
    set -Eeuo pipefail
    export PATH="$1/bin:$PATH"
    GOTOOLCHAIN=auto go install github.com/wailsapp/wails/v2/cmd/wails@v2.10.2
    cd "$2"
    GOTOOLCHAIN=auto make build
  ' bash "$go_bin" "$source"
  install -Dm0755 "$source/build/bin/aether" "$HOME/.local/bin/aether"
  install -Dm0644 "$source/li.oever.aether.desktop" \
    "$HOME/.local/share/applications/li.oever.aether.desktop"
  install -Dm0644 "$source/li.oever.aether.url-handler.desktop" \
    "$HOME/.local/share/applications/li.oever.aether.url-handler.desktop"
  install -Dm0644 "$source/assets/aether-icon-512.png" \
    "$HOME/.local/share/icons/hicolor/512x512/apps/aether.png"
}
install_aether() {
  has_bin aether && return 0
  install_mise
  apt_install git build-essential pkgconf libgtk-3-dev libwebkit2gtk-4.1-dev \
    libgtk-4-dev libadwaita-1-dev libxkbcommon-dev/trixie-backports
  build_archive aether 4.30.0 omacom/aether \
    f67c8d2c6f27f67a755bc279ece5ddb194f1bb165648280b9a7be86904d36ff5 build_aether
  has_bin aether
}

install_dotnet_runtime() {
  if has_bin dotnet && dotnet --list-runtimes | grep '^Microsoft.NETCore.App 10\.' >/dev/null; then return 0; fi
  case "$ARCH" in amd64|arm64) ;; *) die ".NET 10's Microsoft Debian feed does not support $ARCH" ;; esac
  local feed="$DOWNLOADS/packages-microsoft-prod-debian13.deb"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 \
    https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -o "$feed.tmp"
  [[ $(dpkg-deb -f "$feed.tmp" Package) == packages-microsoft-prod ]] || \
    die 'Unexpected Microsoft repository package name'
  mv -f "$feed.tmp" "$feed"
  sudo dpkg -i "$feed"
  sudo apt-get update
  apt_install dotnet-runtime-10.0
  dotnet --list-runtimes | grep '^Microsoft.NETCore.App 10\.' >/dev/null
}

install_pipewire_jack() {
  installed_pkg pipewire-jack && return 0
  apt_install pipewire-jack
  has_bin pw-jack
}

install_one() {
  case "$1" in
    lazydocker) install_lazydocker ;;
    dua-cli) install_dua_cli ;;
    localsend) install_localsend ;;
    mise) install_mise ;;
    obsidian) install_obsidian ;;
    moonlight-qt) install_moonlight_qt ;;
    usage) install_usage ;;
    tobi-try) install_tobi_try ;;
    fonts-ia-writer) install_fonts_ia_writer ;;
    ufw-docker) install_ufw_docker ;;
    gpu-screen-recorder-cli) install_gpu_screen_recorder_cli ;;
    inetutils) install_inetutils ;;
    nss-mdns) install_nss_mdns ;;
    pinta) install_pinta ;;
    nautilus-python) install_nautilus_python ;;
    sushi) install_sushi ;;
    docker-compose-v2) install_docker_compose_v2 ;;
    aether) install_aether ;;
    asdcontrol) install_asdcontrol ;;
    cliamp) install_cliamp ;;
    herdr) install_herdr ;;
    hyprland-preview-share-picker) install_hyprland_preview_share_picker ;;
    omacalc) install_omacalc ;;
    omacut) install_omacut ;;
    omawrite) install_omawrite ;;
    tensaku) install_tensaku ;;
    ttfx) install_ttfx ;;
    tzupdate) install_tzupdate ;;
    dotnet-runtime) install_dotnet_runtime ;;
    pipewire-jack) install_pipewire_jack ;;
    *) die "Unknown component: $1" ;;
  esac
}

selected=()
case "${1:-}" in
  -h|--help) show_usage; exit 0 ;;
  --list) printf '%s\n' "${components[@]}"; exit 0 ;;
  --only)
    (($# == 2)) || die '--only requires one component name'
    valid=0
    for component in "${components[@]}"; do
      if [[ $2 == "$component" ]]; then valid=1; break; fi
    done
    ((valid)) || die "Unknown component: $2"
    selected=("$2") ;;
  --component)
    (($# == 2)) || die '--component requires one component name'
    mkdir -p "$BUILD" "$DOWNLOADS" "$LOG_DIR" "$HOME/.local/bin"
    install_one "$2"
    exit 0 ;;
  '') selected=("${components[@]}") ;;
  *) die "Unknown option: $1 (try --help)" ;;
esac

[[ $EUID -ne 0 ]] || die 'Run as your regular desktop user, not root'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_CODENAME:-} == trixie ]] || die 'Debian 13 Trixie is required'
command -v sudo >/dev/null || die 'sudo is required'
sudo -v
mkdir -p "$BUILD" "$DOWNLOADS" "$LOG_DIR" "$HOME/.local/bin"
sudo apt-get update

failed=()
for component in "${selected[@]}"; do
  printf '\n==> %s\n' "$component"
  if bash "$0" --component "$component" >"$LOG_DIR/$component.log" 2>&1; then
    printf 'OK: %s\n' "$component"
  else
    failed+=("$component")
    printf 'FAILED: %s (see %s)\n' "$component" "$LOG_DIR/$component.log" >&2
  fi
done

if ((${#failed[@]})); then
  printf '\n%d component(s) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
  exit 1
fi
printf '\nAll %d requested components are installed. Logs: %s\n' "${#selected[@]}" "$LOG_DIR"
