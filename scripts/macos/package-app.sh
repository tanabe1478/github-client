#!/usr/bin/env bash
set -euo pipefail

# Packages the MoonBit GitHub Client as a macOS .app bundle and installs it.
#
# Usage:
#   scripts/macos/package-app.sh                 # build + package + install
#   INSTALL_DIR=/Applications scripts/macos/package-app.sh
#
# The bundle embeds libglfw so the app does not depend on Homebrew at runtime.
# It is signed with CODESIGN_IDENTITY when set, else with this Mac's Apple
# Development certificate when one passes an OCSP revocation check, else
# ad-hoc. macOS lets only a properly signed app post notifications as
# itself; an ad-hoc signed app's notifications come through osascript and
# show as Script Editor's. Gatekeeper still blocks the app on other machines
# until it is signed with a Developer ID.

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

# arm64 requires a code signature. macOS treats an app signed with a revoked
# certificate as malware and moves it to the Trash, and `find-identity -v`
# still lists a revoked certificate as valid, so each candidate is checked
# with OCSP first and used by its SHA-1 hash.
certificate_usable() {
  local hash="$1" pem
  pem="$(mktemp)"
  security find-certificate -a -Z -p 2>/dev/null \
    | awk -v h="$hash" '/SHA-1 hash/{on=($3==h)} on&&/BEGIN CERT/{p=1} p{print} /END CERT/{p=0}' > "$pem"
  if [[ -s "$pem" ]] && security verify-cert -c "$pem" -p codeSign -R ocsp -R require >/dev/null 2>&1; then
    rm -f "$pem"
    return 0
  fi
  rm -f "$pem"
  return 1
}
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  for hash in $(security find-identity -v -p codesigning 2>/dev/null \
      | grep '"Apple Development:' | grep -o -E '[0-9A-F]{40}' || true); do
    if certificate_usable "$hash"; then
      IDENTITY="$hash"
      break
    fi
    echo "skip: certificate $hash is revoked or could not be checked" >&2
  done
fi
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Frameworks/libglfw.3.dylib"
codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/github-client"
codesign --force --sign "$IDENTITY" "$APP_DIR"
if [[ "$IDENTITY" == "-" ]]; then
  echo "signed: ad-hoc"
else
  echo "signed: $(codesign -dvv "$APP_DIR" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2-)"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_DIR" "$INSTALL_DIR/"

echo "installed: $INSTALL_DIR/$APP_NAME.app"
