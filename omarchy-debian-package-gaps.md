# Omarchy on Debian package report: failures and skips

Source: `~/.cache/omarchy-debian/package-install-report.log` (installer run on September 22, 2026). These are the report entries, not a fresh package availability check. “Skipped” means APT had no install candidate at that point; the installer may have used a separate download or source fallback afterward.

## Failed APT installs (5)

| Package | Reported reason |
| --- | --- |
| `libgtk-3-dev` | APT install failed |
| `libwebkit2gtk-4.1-dev` | APT install failed |
| `libgtk-4-dev` | APT install failed |
| `libadwaita-1-dev` | APT install failed |
| `libmpv-dev` | APT install failed |

## Skipped APT packages (17)

All were reported as **no candidate** in the enabled APT repositories.

1. `lazydocker`
2. `dua-cli`
3. `localsend`
4. `mise`
5. `obsidian`
6. `moonlight-qt`
7. `usage`
8. `tobi-try`
9. `fonts-ia-writer`
10. `ufw-docker`
11. `gpu-screen-recorder-cli`
12. `inetutils`
13. `nss-mdns`
14. `pinta`
15. `nautilus-python`
16. `sushi`
17. `docker-compose-v2`

## Upstream sources and Debian alternatives

These are project-owned pages or Debian package pages checked on September 23, 2026. Links identify sources; no software was downloaded or installed while researching this list. A “fallback” below means the current installer contains a separate download or source-build path, not that the fallback succeeded on this machine.

### Current status of the five Debian package-name mismatches

Checked with `dpkg-query` on September 23, 2026. The historical “skipped” lines above remain accurate for the earlier installer run; these Debian packages are installed now.

| Original skipped name | Installed Debian package |
| --- | --- |
| `inetutils` | `inetutils-telnet` |
| `nss-mdns` | `libnss-mdns` |
| `nautilus-python` | `python3-nautilus` |
| `sushi` | `gnome-sushi` |
| `docker-compose-v2` | `docker-compose` (`docker compose version` reports 2.26.1) |

| Skipped APT name | Source or better Debian package | Current installer |
| --- | --- | --- |
| `lazydocker` | [Upstream repository](https://github.com/jesseduffield/lazydocker) | Has a source-build fallback. |
| `dua-cli` | [Upstream repository](https://github.com/Byron/dua-cli) | Has a source-build fallback. |
| `localsend` | [Official Linux `.deb` releases](https://github.com/localsend/localsend/releases) | Has a pinned `.deb` download. |
| `mise` | [Official installation guide](https://mise.jdx.dev/installing-mise.html) and [repository](https://github.com/jdx/mise) | Has a pinned binary download. |
| `obsidian` | [Official Linux download page](https://obsidian.md/download) (includes `.deb`) | No separate fallback found. Obsidian's application source is not in its public releases repository. |
| `moonlight-qt` | [Upstream repository and Linux release options](https://github.com/moonlight-stream/moonlight-qt) | Has a source-build fallback. |
| `usage` | [Upstream repository](https://github.com/jdx/usage) | Has a source-build fallback. |
| `tobi-try` | [Upstream `try` repository and installation instructions](https://github.com/tobi/try) | Has a pinned source fallback. |
| `fonts-ia-writer` | [iA Writer font repository](https://github.com/iaolo/iA-Fonts) | No separate fallback found. Review the font license and attribution before redistributing. |
| `ufw-docker` | [Upstream script and install instructions](https://github.com/chaifeng/ufw-docker) | Has a pinned script download. |
| `gpu-screen-recorder-cli` | [Upstream source and install instructions](https://git.dec05eba.com/gpu-screen-recorder/about/) | Has a source-build fallback. Upstream also links to a Debian package, which may be available in a different suite or at a later date. |
| `inetutils` | [Debian's `inetutils` source and its individual binary packages](https://packages.debian.org/source/trixie/inetutils) | No fallback. Select the needed tool, such as `inetutils-tools` or `inetutils-telnet`; `inetutils` itself is a source package name. |
| `nss-mdns` | [Debian `libnss-mdns`](https://packages.debian.org/trixie/libnss-mdns) | No fallback. Replace the APT name with `libnss-mdns` if mDNS resolution is intended. |
| `pinta` | [Official Pinta downloads](https://www.pinta-project.com/releases/) and [source repository](https://github.com/PintaProject/Pinta) | No separate fallback found. Official Linux downloads include Flatpak. |
| `nautilus-python` | [Debian `python3-nautilus`](https://packages.debian.org/trixie/python3-nautilus) | No fallback. Replace the APT name with `python3-nautilus`. |
| `sushi` | [Debian `gnome-sushi`](https://packages.debian.org/trixie/gnome-sushi) | No fallback. Replace the APT name with `gnome-sushi`. |
| `docker-compose-v2` | [Debian `docker-compose`](https://packages.debian.org/trixie/docker-compose) or [Docker's Compose plugin instructions](https://docs.docker.com/compose/install/linux/) | No fallback. Debian's package is named `docker-compose`; Docker's repository uses `docker-compose-plugin`. |
