#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$root/scripts/validate.py"
"$root/bridge/test.sh"
python3 "$root/scripts/customizations.py" check
python3 "$root/scripts/test_restore.py"
