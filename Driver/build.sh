#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MAC_KERNEL_SDK:-$ROOT/Vendor/MacKernelSDK}"
OUT="$ROOT/build/Driver/ROGFirmwareProbe.kext"
[[ -d "$SDK/Headers" && -f "$SDK/Library/x86_64/libkmod.a" ]] || { echo 'Set MAC_KERNEL_SDK to a MacKernelSDK checkout; see README.md.' >&2; exit 1; }
mkdir -p "$OUT/Contents/MacOS"
clang++ -target x86_64-apple-macos10.15 -std=gnu++17 -mkernel -DKERNEL -DKERNEL_PRIVATE -nostdinc -I"$SDK/Headers" -fno-exceptions -fno-rtti -fapple-kext -fno-builtin -fno-stack-protector -mno-red-zone -Wall -Wextra -Werror -Wno-unused-parameter -c "$ROOT/Driver/ROGFirmwareProbe.cpp" -o "$ROOT/build/Driver/probe.o"
clang++ -target x86_64-apple-macos10.15 -nostdlib -Wl,-kext -Wl,-undefined,dynamic_lookup -Wl,-no_fixup_chains "$ROOT/build/Driver/probe.o" "$SDK/Library/x86_64/libkmod.a" -o "$OUT/Contents/MacOS/ROGFirmwareProbe"
cp "$ROOT/Driver/Info.plist" "$OUT/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$OUT"
codesign --verify --deep --strict "$OUT"
echo "Built $OUT. Not installed."
