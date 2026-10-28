#!/bin/zsh
# Builds Zenith.app into ./build. Pass --install to copy it to /Applications and launch it.
#
# The core's tests run first; a failure stops the build.
#
# Set ZENITH_SIGN_IDENTITY (or NOVA_SIGN_IDENTITY) to your "Apple Development: …" identity
# (see `security find-identity -p codesigning -v`) to sign with it; otherwise it's ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ Tests"
swift test

echo "→ Building"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP=build/Zenith.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Zenith" "$APP/Contents/MacOS/Zenith"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: build AppIcon.icns from the 1024px PNG.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${ZENITH_SIGN_IDENTITY:-${NOVA_SIGN_IDENTITY:--}}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Zenith 2>/dev/null || true
    # Wait for the old copy to quit, or launching the new one races it.
    for _ in {1..20}; do pgrep -x Zenith >/dev/null || break; sleep 0.25; done
    rm -rf /Applications/Zenith.app
    cp -R "$APP" /Applications/
    open /Applications/Zenith.app
    echo "Installed and launched /Applications/Zenith.app"
fi
