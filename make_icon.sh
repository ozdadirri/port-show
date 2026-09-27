#!/bin/bash
# Generates the .icns app icon (":80" on an ivory rounded square, clay colon) using AppKit.
set -euo pipefail

OUT_ICNS="$1"
TMP_DIR="$(mktemp -d)"
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$TMP_DIR/gen.swift" <<'SWIFT'
import AppKit

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments[1]

let ivory = NSColor(srgbRed: 0.980, green: 0.976, blue: 0.961, alpha: 1)   // #faf9f5
let border = NSColor(srgbRed: 0.863, green: 0.851, blue: 0.816, alpha: 1)  // #dcd9d0
let slate = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.075, alpha: 1)   // #141413
let clay = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)    // #d97757

func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    // macOS icon grid: the tile is 824/1024 of the canvas, centred, leaving room for the shadow.
    let tile = size * 824 / 1024
    let tileRect = NSRect(x: (size - tile) / 2, y: (size - tile) / 2 + size * 0.01, width: tile, height: tile)
    let radius = tile * 0.225
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.set()
    ivory.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    border.setStroke()
    tilePath.lineWidth = max(1, tile * 0.015)
    tilePath.stroke()

    // Heavier weight at small sizes so the digits survive downscaling.
    let font = NSFont.monospacedSystemFont(ofSize: tile * 0.36, weight: pixels <= 64 ? .heavy : .bold)
    let text = NSMutableAttributedString(string: ":80", attributes: [.font: font, .foregroundColor: slate])
    text.addAttribute(.foregroundColor, value: clay, range: NSRange(location: 0, length: 1))
    let textSize = text.size()
    // Centre the digits' cap height on the tile (draw(at:) places the line box, baseline sits above the descent).
    let baseline = tileRect.midY - font.capHeight / 2
    let origin = NSPoint(x: tileRect.midX - textSize.width / 2, y: baseline + font.descender)
    text.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for pixels in sizes {
    if let png = renderIcon(pixels: pixels) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(pixels)x\(pixels).png"))
    }
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

if [ -n "${KEEP_ICON_PNG:-}" ]; then cp "$TMP_DIR/icon_1024x1024.png" "$KEEP_ICON_PNG"; cp "$TMP_DIR/icon_64x64.png" "${KEEP_ICON_PNG%.png}-64.png"; fi

iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
rm -rf "$TMP_DIR"
