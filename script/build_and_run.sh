#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/dist/ROG Control for macOS.app"
BUILD="$ROOT_DIR/build"
VERSION="$(/bin/cat "$ROOT_DIR/VERSION")"
case "$MODE" in run|--verify|--logs|--telemetry|--debug|--build-only) ;; *) echo 'Usage: script/build_and_run.sh [--build-only|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;; esac
if [[ "$MODE" != --build-only ]]; then /usr/bin/pkill -x ROGControl >/dev/null 2>&1 || true; fi
/bin/mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
COMMON=(-fobjc-arc -target x86_64-apple-macos14.0 -Wall -Wextra -Werror -I"$ROOT_DIR/Sources")
SHARED=("$ROOT_DIR/Sources/Bridge.m" "$ROOT_DIR/Sources/Sensors.m" "$ROOT_DIR/Sources/RMSensors.m")
/usr/bin/clang "${COMMON[@]}" "$ROOT_DIR/Sources/Helper.m" "${SHARED[@]}" -framework Foundation -framework IOKit -framework Security -o "$BUILD/ROGControlHelper"
/usr/bin/codesign --force --sign - --timestamp=none "$BUILD/ROGControlHelper"
/usr/bin/clang "${COMMON[@]}" "$ROOT_DIR/Sources/App.m" "$ROOT_DIR/Sources/TuningController.m" "$ROOT_DIR/Sources/TuningPreset.m" "$ROOT_DIR/Sources/TuningCurveView.m" "${SHARED[@]}" -framework Cocoa -framework IOKit -framework UniformTypeIdentifiers -o "$APP/Contents/MacOS/ROGControl"
/usr/bin/clang "${COMMON[@]}" "$ROOT_DIR/Tools/profile-client.m" -framework Foundation -framework IOKit -o "$BUILD/profile-client"
/usr/bin/clang "${COMMON[@]}" "$ROOT_DIR/Tools/tuning-client.m" "${SHARED[@]}" -framework Foundation -framework IOKit -o "$BUILD/tuning-client"
/bin/cp "$BUILD/ROGControlHelper" "$APP/Contents/Resources/ROGControlHelper"
HELPER_HASH=$(/usr/bin/shasum -a 256 "$BUILD/ROGControlHelper" | /usr/bin/awk '{print $1}')
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ROG Control for macOS</string>
<key>CFBundleDisplayName</key><string>ROG Control for macOS</string>
<key>CFBundleExecutable</key><string>ROGControl</string>
<key>CFBundleIdentifier</key><string>com.macdriver.ROGControl</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>ROGHelperSHA256</key><string>$HELPER_HASH</string>
</dict></plist>
PLIST
if [[ -f "$ROOT_DIR/LICENSE" ]]; then /bin/cp "$ROOT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"; fi
/bin/cp "$ROOT_DIR/THIRD_PARTY.md" "$APP/Contents/Resources/THIRD_PARTY.md"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/ROGControl" --test-requests
if [[ "$MODE" == --build-only ]]; then exit 0; fi
if [[ "$MODE" == --debug ]]; then /usr/bin/lldb -- "$APP/Contents/MacOS/ROGControl"; exit; fi
/usr/bin/open -n "$APP"
case "$MODE" in
 --verify) /bin/sleep 1; /usr/bin/pgrep -x ROGControl ;;
 --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "ROGControl" OR process == "ROGControlHelper"' ;;
esac
