# Omarchy Debian package bridge

See the [top-level installation guide](../README.md) for setup and scope.

This bridge keeps Debian and APT responsible for the host operating system. It
provides pacman and AUR in a rootless Arch Distrobox, exports graphical apps to
the host launcher, and adds Arch updates to `omarchy update`.

The top-level `install.sh` invokes this bridge automatically. For an existing
Omarchy-on-Debian installation, run `./activate.sh` from a normal desktop
terminal. It installs Debian's
`distrobox` and `podman` packages, creates the Arch box, bootstraps `yay`, then
links the commands into `~/.local/bin`. It needs network access and sudo for
the Debian packages. The Distrobox shares desktop sockets and can access your
host home directory; review AUR build recipes before installing them.

`~/.local/bin/omarchy` intercepts only package installation and update routes.
The packaged Omarchy dispatcher searches `/usr/bin` directly, so a PATH shim is
needed for these routes; other commands continue through `/usr/bin/omarchy`.
The read-only `pacman` shim includes Debian packages and Arch apps exported to
the desktop in Omarchy's menu guards. Arch's internal libraries and services do
not count as host installations. `omarchy-arch refresh-cache` updates package
data after changes made directly inside the Arch box.

The Debian system adapters use Timeshift RSYNC snapshots on a separate
filesystem, Debian's swap/resume configuration, `update-grub`, and
`update-initramfs`. Run `./activate-system.sh --snapshot-mount PATH` once from
a normal desktop terminal to install Timeshift and make the first snapshot.
Afterward, use `omarchy snapshot create|list|restore`.

`omarchy channel set stable|rc|edge` chooses which upstream Omarchy source to
inspect. `omarchy release stage` fetches that channel's latest source and
checks whether the local Debian patch can apply to it. It only stages source;
upstream Arch package releases do not update Debian's installed Omarchy files.
Each new release needs a Debian port and migration review before deployment.

Examples after activation:

```sh
omarchy pkg install --debian inkscape
omarchy pkg install --arch mpv
omarchy pkg install --aur visual-studio-code-bin
omarchy pkg drop visual-studio-code-bin
omarchy pkg remove --arch visual-studio-code-bin
omarchy-arch run bash
omarchy-arch export visual-studio-code-bin
omarchy update
omarchy channel current
omarchy release stage
```

The host `pacman` command remains read-only. Run real pacman via
`omarchy-arch run /usr/bin/pacman ...`.

Known scope: system services, drivers, PAM modules, and shared libraries must
be installed with APT on Debian. Arch packages stay in the box.
