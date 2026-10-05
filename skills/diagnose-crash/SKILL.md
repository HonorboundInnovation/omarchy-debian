---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this Omarchy-on-Debian machine, using
  systemd-coredump and logs when available. Distinguish Debian host processes
  from programs in the Arch Distrobox before selecting packages or symbols.
  Use when a process has segfaulted, aborted, or otherwise dumped core, when asked
  why an application crashed or disappeared, or when a "Process crashed:" desktop
  notification is acted on. Triggers: crash, segfault, SIGSEGV, SIGABRT, core dump,
  coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers routing a confirmed bug to its proper project — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

## Identify the runtime before using package tools

This system has two package environments. Debian/APT owns the host; real pacman
and yay run in the `omarchy-arch` Distrobox. Use the executable path, command
line, cgroup/container metadata, and package ownership to decide which one
crashed. Do not assume every Omarchy desktop process is Arch-based.

- For a host executable, check `dpkg -S <path>` and Debian package versions.
- For an Arch-box executable, inspect it with `omarchy-arch run
  /usr/bin/pacman -Qo <path>` and `omarchy-arch run /usr/bin/pacman -Q <pkg>`.
  Paths in the host coredump record may need mapping to their in-box paths.
- The host `pacman` on `PATH` is a read-only menu compatibility shim. It cannot
  establish Arch package ownership. Use the real binary through `omarchy-arch`.

The host may record a container process's core, but the Arch box is not assumed
to run its own systemd-coredump service. Start with the host's `coredumpctl`
and verify where any core and executable can be accessed before debugging.

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** Check APT history for Debian-owned programs and
  the Arch box's `/var/log/pacman.log` for its packages. A crash starting after
  an update is a lead, not proof of causation.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

## Symbolize when you can

For Debian-owned binaries, use `gdb` and matching Debian `-dbgsym` packages
when already available. Debian's debuginfod service can also supply symbols;
it may download symbol data when enabled:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.debian.net" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

For Arch-box binaries, use symbols and executable files matching the Arch
package versions inside that box. Debian `-dbgsym` packages and Debian's
debuginfod will not symbolize Arch binaries correctly. Confirm access to the
host-recorded core from the chosen debugger environment before assuming a
container-side `gdb` command will work.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory.

## If it is an Omarchy bug

Most application crashes are bugs in those applications, not Omarchy's doing.
Distinguish application upstream, Debian packaging, Arch packaging/AUR recipes,
the Debian bridge, and official Omarchy code before proposing a report. Read
[`reporting.md`](reporting.md) for the routing and filing requirements.
