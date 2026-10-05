#!/usr/bin/env python3
"""Offline validation of the consolidated source and pinned runtime fixes."""

import ast
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    shell = []
    lua = []
    python_count = 0
    for path in ROOT.rglob("*"):
        if ".git" in path.parts or path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if data.startswith((b"#!/usr/bin/env bash", b"#!/bin/bash", b"#!/bin/sh")):
            subprocess.run(["bash", "-n", str(path)], check=True)
            shell.append(str(path))
        if path.suffix == ".py":
            ast.parse(data, filename=str(path))
            python_count += 1
        if path.suffix == ".json":
            json.loads(data)
        if path.suffix == ".lua":
            lua.append(path)
    print(f"Syntax passed: {len(shell)} shell scripts, {python_count} Python files; JSON parsed.")
    # bash -n does not parse executable scripts embedded in installer heredocs.
    generated_count = 0
    with tempfile.TemporaryDirectory() as temp:
        for installer in ROOT.glob("install-*.sh"):
            content = installer.read_text()
            for match in re.finditer(r"<<'([A-Z_]+)'\n(.*?)\n\1\n", content, re.S):
                body = match[2]
                if body.startswith("#!/usr/bin/env bash"):
                    generated = Path(temp) / f"generated-{generated_count}.sh"
                    generated.write_text(body)
                    subprocess.run(["bash", "-n", str(generated)], check=True)
                    generated_count += 1
                elif match[1] == "PY":
                    ast.parse(body, filename=f"{installer.name}:{match[1]}")
    print(f"Installer heredocs validated, including {generated_count} generated shell scripts.")
    if shutil.which("luac"):
        for path in lua:
            subprocess.run(["luac", "-p", str(path)], check=True)
        print(f"Lua syntax passed: {len(lua)} files.")
    shellcheck = os.environ.get("SHELLCHECK") or shutil.which("shellcheck")
    if shellcheck:
        subprocess.run([shellcheck, "--severity=warning", *shell], check=True)
        print("ShellCheck passed at warning severity.")
    else:
        print("ShellCheck unavailable; set SHELLCHECK to enable lint.")

    upstream = Path.home() / ".local/share/omarchy-debian/upstream"
    expected = "c668141e9c42b13c80c9ca4ea108e11708c5e8a5"
    if (upstream / ".git").is_dir():
        with tempfile.TemporaryDirectory() as temp:
            archive = subprocess.Popen(["git", "-C", str(upstream), "archive", expected],
                                       stdout=subprocess.PIPE)
            try:
                subprocess.run(["tar", "-x", "-C", temp], stdin=archive.stdout, check=True)
            finally:
                archive.stdout.close()
            if archive.wait():
                raise RuntimeError("Could not archive pinned upstream source")
            subprocess.run(["git", "-C", temp, "apply", "--check",
                            str(ROOT / "omarchy-debian-runtime.patch")], check=True)
            subprocess.run(["git", "-C", temp, "apply",
                            str(ROOT / "omarchy-debian-runtime.patch")], check=True)
            subprocess.run(["bash", "-n", str(Path(temp) / "bin/omarchy-menu-keybindings")], check=True)
        print("Runtime patch applies cleanly to the pinned Omarchy source.")
    else:
        print("Pinned source checkout unavailable; runtime patch test skipped.")


if __name__ == "__main__":
    main()
