#!/bin/zsh
# Builds KeyPace.app with SwiftPM + Xcode's tools (actool for the icon).
#   ./build.sh            -> build/KeyPace.app
#   ./build.sh install    -> also copies it to /Applications and launches it
#   ./build.sh release    -> universal (Apple silicon + Intel) build, zipped in dist/ for GitHub
set -euo pipefail
cd "$(dirname "$0")"

# Speed maths and key classification must pass their tests before anything is built.
if [[ -z "${SKIP_TESTS:-}" ]]; then
  swift test --quiet
fi
# Release builds contain both architectures so they run on every Mac that has macOS 26.
SWIFT_ARGS=(-c release)
[[ "${1:-}" == "release" ]] && SWIFT_ARGS+=(--arch arm64 --arch x86_64)
swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/KeyPace"

# Compile the layered Liquid Glass icon (Resources/AppIcon.icon, editable in Icon Composer).
ICON_OUT="$BIN_DIR/icon"
rm -rf "$ICON_OUT"; mkdir -p "$ICON_OUT"
xcrun actool Resources/AppIcon.icon --compile "$ICON_OUT" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null

APP=build/KeyPace.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeyPace"
# SwiftPM records the deployment target (26.0) as the SDK version even with Xcode selected.
# macOS picks the design generation from that field, so stamp the SDK actually used (27.x).
vtool -set-build-version macos 26.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/KeyPace" "$APP/Contents/MacOS/KeyPace"
# Guard: an SDK version below 26 makes macOS run the app in compatibility mode (no Liquid Glass).
SDK_IN_BINARY="$(otool -l "$APP/Contents/MacOS/KeyPace" | awk '/LC_BUILD_VERSION/{f=1} f && $1=="sdk"{print $2; exit}')"
if [[ "${SDK_IN_BINARY%%.*}" -lt 26 ]]; then
  echo "error: binary was linked against SDK $SDK_IN_BINARY; select Xcode with xcode-select" >&2; exit 1
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON_OUT/Assets.car" "$ICON_OUT/AppIcon.icns" "$APP/Contents/Resources/"
# Sign with the local "KeyPace Local Signing" certificate when it exists. A stable
# certificate keeps the app's identity the same across rebuilds, so Input Monitoring and the
# Keychain's "Always Allow" for the ApeKey survive updates. Falls back to ad-hoc signing.
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk '/"KeyPace Local Signing"/ {print $2; exit}')"
codesign --force --sign "${SIGN_ID:--}" --identifier com.charl.keypace "$APP"
echo "Signed with: ${SIGN_ID:-ad-hoc}"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x KeyPace 2>/dev/null || true
  rm -rf /Applications/KeyPace.app
  cp -R "$APP" /Applications/
  open /Applications/KeyPace.app
  echo "Installed to /Applications/KeyPace.app"
fi

if [[ "${1:-}" == "release" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
  mkdir -p dist
  ZIP="dist/KeyPace-$VERSION.zip"
  rm -f "$ZIP"
  # ditto keeps the code signature intact (plain zip can break it); --norsrc leaves out
  # macOS file labels, which would show up as a __MACOSX folder on other systems.
  ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
  shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
  echo "Release archive: $ZIP ($(lipo -archs "$APP/Contents/MacOS/KeyPace"))"
fi
