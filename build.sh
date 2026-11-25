#!/usr/bin/env bash
# Builds CFMod.dylib for iOS (arm64 + arm64e). Needs only the Xcode iPhoneOS SDK,
# so it runs unchanged on a macOS GitHub runner or a local Mac.
set -euo pipefail

cd "$(dirname "$0")"
OUT="${OUT:-build}"
MIN_IOS="${MIN_IOS:-15.0}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

mkdir -p "$OUT"

SRC=$(ls src/*.mm src/*.cpp)
CFLAGS=(
  -std=c++17 -fobjc-arc -O2 -g0
  -fvisibility=hidden -fno-rtti
  -Wall -Wno-unused-parameter -Wno-deprecated-declarations
  -Isrc
  -arch arm64 -arch arm64e
  -miphoneos-version-min="$MIN_IOS"
  -isysroot "$SDK"
  -DNDEBUG
)
LDFLAGS=(
  -dynamiclib
  -install_name @executable_path/Frameworks/CFMod.dylib
  -framework UIKit -framework Foundation
  -framework CoreGraphics -framework QuartzCore
  -Wl,-dead_strip
)

echo "[*] sdk     $SDK"
echo "[*] sources $(echo "$SRC" | wc -w | tr -d ' ') files"

# shellcheck disable=SC2086
xcrun --sdk iphoneos clang++ "${CFLAGS[@]}" "${LDFLAGS[@]}" -o "$OUT/CFMod.dylib" $SRC

# ad-hoc sign so dyld will load it inside a Sideloadly / TrollStore signed app
if command -v ldid >/dev/null 2>&1; then
  ldid -S "$OUT/CFMod.dylib"
elif command -v codesign >/dev/null 2>&1; then
  codesign -f -s - "$OUT/CFMod.dylib"
fi

echo "[+] $OUT/CFMod.dylib"
ls -l "$OUT/CFMod.dylib"
