#!/bin/bash
# Generates an .icns app icon (a rounded square with a network glyph) using AppKit.
set -euo pipefail

OUT_ICNS="$1"
TMP_DIR="$(mktemp -d)"
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$TMP_DIR/gen.swift" <<'SWIFT'
import AppKit

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments[1]

func makeIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = CGFloat(size) * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1.0).setFill() // clay
    bgPath.fill()

    if let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.52, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        configured.isTemplate = true
        let symSize = configured.size
        let drawRect = NSRect(
            x: (CGFloat(size) - symSize.width) / 2,
            y: (CGFloat(size) - symSize.height) / 2,
            width: symSize.width,
            height: symSize.height
        )
        NSColor.white.set()
        configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

for size in sizes {
    let img = makeIcon(size: size)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size).png"))
}
SWIFT

swift "$TMP_DIR/gen.swift" "$TMP_DIR"

cp "$TMP_DIR/icon_16x16.png" "$ICONSET/icon_16x16.png"
cp "$TMP_DIR/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
cp "$TMP_DIR/icon_32x32.png" "$ICONSET/icon_32x32.png"
cp "$TMP_DIR/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
cp "$TMP_DIR/icon_128x128.png" "$ICONSET/icon_128x128.png"
cp "$TMP_DIR/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$TMP_DIR/icon_256x256.png" "$ICONSET/icon_256x256.png"
cp "$TMP_DIR/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$TMP_DIR/icon_512x512.png" "$ICONSET/icon_512x512.png"
cp "$TMP_DIR/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
rm -rf "$TMP_DIR"
