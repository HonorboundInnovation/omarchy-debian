#!/usr/bin/env python3
"""Install the maintained Debian skills and link them into agent discovery paths."""

from pathlib import Path
import os
import shutil


def main():
    home = Path.home()
    source = Path(__file__).resolve().parent / "skills"
    target = home / ".local/share/omarchy-debian/skills"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("omarchy", "diagnose-crash"):
        if not (source / name / "SKILL.md").is_file():
            raise SystemExit(f"Missing bundled skill: {source / name}")
    for name in ("omarchy", "diagnose-crash"):
        # Update this installer's maintained copies, preserving independent agent skills.
        shutil.copytree(source / name, target / name, dirs_exist_ok=True)
    roots = [home / path for path in (
        ".agents/skills", ".claude/skills", ".pi/agent/skills",
        ".gemini/config/skills", ".hermes/skills", ".config/opencode/skills",
    )]
    roots.append(Path(os.environ.get("CODEX_HOME", str(home / ".codex"))) / "skills")
    profiles = home / ".hermes/profiles"
    if profiles.is_dir():
        roots.extend(p / "skills" for p in profiles.iterdir() if p.is_dir())
    for root in roots:
        root.mkdir(parents=True, exist_ok=True)
        for name in ("omarchy", "diagnose-crash"):
            link = root / name
            if link.exists() or link.is_symlink():
                print(f"Preserving existing skill: {link}")
                continue
            link.symlink_to(target / name)
            print(f"Installed {link} -> {target / name}")


if __name__ == "__main__":
    main()
