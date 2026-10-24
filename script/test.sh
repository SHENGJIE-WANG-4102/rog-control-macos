#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/script/build_and_run.sh" --build-only
python3 "$ROOT/Tests/test-profile-contract.py"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-rm-sensors.m" -framework Foundation -framework IOKit -o "$ROOT/build/test-rm-sensors"
"$ROOT/build/test-rm-sensors"
