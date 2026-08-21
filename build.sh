#!/bin/bash
# Builds DisplayHelper and assembles it into a runnable .app bundle in ./dist.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DisplayHelper"
BUNDLE="dist/${APP_NAME}.app"
MIN_MACOS="13.0"

echo "==> Building (release, universal)"
mkdir -p build
swiftc -O -target arm64-apple-macos${MIN_MACOS}  main.swift -o "build/${APP_NAME}-arm64"
swiftc -O -target x86_64-apple-macos${MIN_MACOS} main.swift -o "build/${APP_NAME}-x86_64"
lipo -create -output "build/${APP_NAME}" \
  "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64"

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp "build/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Ad-hoc signature. Enough for local use; distributing to another Mac would
# need a Developer ID signature and notarization. A stable signature also
# keeps the Accessibility grant from being invalidated on every rebuild.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "${BUNDLE}" >/dev/null 2>&1

echo "==> Done: ${BUNDLE}"
echo "    Run it with:  open ${BUNDLE}"
echo "    Install with: cp -R ${BUNDLE} ~/Applications/"
