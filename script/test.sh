#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/script/build_and_run.sh" --build-only
python3 "$ROOT/Tests/test-profile-contract.py"
