#!/usr/bin/env bash
set -euo pipefail

# Packages the MoonBit GitHub Client as a macOS .app bundle and installs it.
#
# Usage:
#   scripts/macos/package-app.sh                 # build + package + install
#   INSTALL_DIR=/Applications scripts/macos/package-app.sh
#
# The bundle embeds libglfw so the app does not depend on Homebrew at runtime.
# Signing is ad-hoc: fine for this machine, Gatekeeper will still block the app
# on other machines until it is signed with a Developer ID.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="MoonBit GitHub Client"
BUNDLE_ID="dev.moonbit.github-client"
VERSION="0.1.0"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BINARY="$REPO_ROOT/_build/native/release/build/tanabe1478/github-client/cmd/github_client/github_client.exe"
GLFW_REFERENCE="/opt/homebrew/opt/glfw/lib/libglfw.3.dylib"

GLFW_PREFIX="$(brew --prefix glfw 2>/dev/null || true)"
if [[ -z "$GLFW_PREFIX" || ! -f "$GLFW_PREFIX/lib/libglfw.3.dylib" ]]; then
  echo "GLFW was not found. Run: brew install glfw" >&2
  exit 1
fi

cd "$REPO_ROOT"
mise exec -- moon build cmd/github_client --target native --release
if [[ ! -f "$BINARY" ]]; then
  echo "release binary not found: $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BINARY" "$APP_DIR/Contents/MacOS/github-client"

# Bundle libglfw and point the executable at the embedded copy.
cp "$GLFW_PREFIX/lib/libglfw.3.dylib" "$APP_DIR/Contents/Frameworks/"
install_name_tool -id "@executable_path/../Frameworks/libglfw.3.dylib" \
  "$APP_DIR/Contents/Frameworks/libglfw.3.dylib"
install_name_tool -change "$GLFW_REFERENCE" "@executable_path/../Frameworks/libglfw.3.dylib" \
  "$APP_DIR/Contents/MacOS/github-client"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>github-client</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Generate a simple icon (dark rounded square + GH) without external assets.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
render_icon() {
  local pixels="$1" out="$2"
  PIXELS="$pixels" OUT="$out" swift -e '
import Cocoa
let pixels = Int(ProcessInfo.processInfo.environment["PIXELS"]!)!
let out = ProcessInfo.processInfo.environment["OUT"]!
let size = CGFloat(pixels)
guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let inset = size * 0.04
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.21, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: size * 0.23, yRadius: size * 0.23).fill()
let font = NSFont.boldSystemFont(ofSize: size * 0.42)
let attrs: [NSAttributedString.Key: Any] = [
  .font: font,
  .foregroundColor: NSColor.white,
]
let text = "GH" as NSString
let textSize = text.size(withAttributes: attrs)
text.draw(
  at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 - size * 0.02),
  withAttributes: attrs
)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: out))
' >/dev/null 2>&1
}
for s in 16 32 128 256 512; do
  render_icon "$s" "$ICONSET/icon_${s}x${s}.png"
  render_icon "$((s * 2))" "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

# arm64 requires a code signature; ad-hoc is enough for local installs.
codesign --force --sign - "$APP_DIR/Contents/Frameworks/libglfw.3.dylib"
codesign --force --sign - "$APP_DIR/Contents/MacOS/github-client"
codesign --force --sign - "$APP_DIR"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_DIR" "$INSTALL_DIR/"

echo "installed: $INSTALL_DIR/$APP_NAME.app"
