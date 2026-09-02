#!/usr/bin/env swift
// Generates Resources/AppIcon.icns: a waveform glyph on a blue
// gradient, rendered at all required sizes and packed with iconutil.
// Usage: swift scripts/make-icon.swift

import AppKit

let projectRoot = URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
    .deletingLastPathComponent()  // scripts/
    .deletingLastPathComponent()  // project root
let iconsetURL = projectRoot.appendingPathComponent("Resources/AppIcon.iconset")
let icnsURL = projectRoot.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // macOS icons float inside ~10% padding.
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.62, green: 0.38, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.30, green: 0.14, blue: 0.62, alpha: 1)
    )!
    gradient.draw(in: background, angle: -70)

    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symbolRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symbolRect)
        symbolRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let glyphWidth = rect.width * 0.58
        let glyphHeight = glyphWidth * (symbol.size.height / symbol.size.width)
        tinted.draw(in: NSRect(
            x: rect.midX - glyphWidth / 2,
            y: rect.midY - glyphHeight / 2,
            width: glyphWidth, height: glyphHeight
        ))
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for base in [16, 32, 128, 256, 512] {
    for (suffix, pixels) in [("", base), ("@2x", base * 2)] {
        let image = renderIcon(pixels: pixels)
        let name = "icon_\(base)x\(base)\(suffix).png"
        try writePNG(image, pixels: pixels, to: iconsetURL.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)
print(iconutil.terminationStatus == 0 ? "Wrote \(icnsURL.path)" : "iconutil failed")
exit(iconutil.terminationStatus)
