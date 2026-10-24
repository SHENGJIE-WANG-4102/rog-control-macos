#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/script/build_and_run.sh" --build-only
python3 "$ROOT/Tests/test-profile-contract.py"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-rm-sensors.m" -framework Foundation -framework IOKit -o "$ROOT/build/test-rm-sensors"
"$ROOT/build/test-rm-sensors"
/usr/bin/clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/Tests/test-tuning-engine.cpp" -o "$ROOT/build/test-tuning-engine"
"$ROOT/build/test-tuning-engine"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-tuning-requests.m" "$ROOT/Sources/Bridge.m" "$ROOT/Sources/Sensors.m" "$ROOT/Sources/RMSensors.m" -framework Foundation -framework IOKit -o "$ROOT/build/test-tuning-requests"
"$ROOT/build/test-tuning-requests"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-tuning-ui.m" "$ROOT/Sources/TuningPreset.m" "$ROOT/Sources/TuningCurveView.m" "$ROOT/Sources/Bridge.m" "$ROOT/Sources/Sensors.m" "$ROOT/Sources/RMSensors.m" -framework Cocoa -framework IOKit -framework UniformTypeIdentifiers -o "$ROOT/build/test-tuning-ui"
"$ROOT/build/test-tuning-ui"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-curve-editing.m" -framework Cocoa -o "$ROOT/build/test-curve-editing"
"$ROOT/build/test-curve-editing"
/usr/bin/clang -fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT/Sources" "$ROOT/Tests/test-single-window.m" "$ROOT/Sources/TuningController.m" "$ROOT/Sources/TuningPreset.m" "$ROOT/Sources/TuningCurveView.m" "$ROOT/Sources/Bridge.m" "$ROOT/Sources/Sensors.m" "$ROOT/Sources/RMSensors.m" -framework Cocoa -framework IOKit -framework UniformTypeIdentifiers -o "$ROOT/build/test-single-window"
"$ROOT/build/test-single-window"
