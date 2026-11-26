#!/usr/bin/env swift
// make-icon.swift — рисует иконку приложения и складывает её в Resources/AppIcon.icns.
//
// Иконка генерируется кодом (без внешних ассетов и графических редакторов):
// тёмный «кофейный» градиентный скруглённый квадрат и светлая чашка.
// Запуск: swift Scripts/make-icon.swift [output.icns]

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent("Resources/AppIcon.icns")

/// Один кадр иконки в квадрате `pixels`×`pixels`.
func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let full = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    full.fill()

    // Фон: скруглённый квадрат с отступом в стиле macOS-иконок.
    let inset = size * 0.085
    let plate = full.insetBy(dx: inset, dy: inset)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.225, yRadius: plate.height * 0.225)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.31, green: 0.19, blue: 0.11, alpha: 1),  // тёплый кофейный
        NSColor(srgbRed: 0.11, green: 0.07, blue: 0.05, alpha: 1),  // почти чёрный
    ])!
    gradient.draw(in: platePath, angle: -90)

    // Тонкая светлая окантовка — «стеклянный» край плитки.
    NSColor(white: 1, alpha: 0.10).setStroke()
    platePath.lineWidth = max(1, size * 0.006)
    platePath.stroke()

    let cx = size / 2
    let cream = NSColor(srgbRed: 0.96, green: 0.90, blue: 0.80, alpha: 1)
    let coffee = NSColor(srgbRed: 0.11, green: 0.07, blue: 0.05, alpha: 1)

    // Ручка чашки: кольцо справа, тело чашки потом перекроет его левую часть.
    let handleRect = NSRect(
        x: cx + size * 0.085,
        y: size * 0.365,
        width: size * 0.215,
        height: size * 0.215
    )
    let handle = NSBezierPath(ovalIn: handleRect)
    handle.lineWidth = size * 0.055
    cream.setStroke()
    handle.stroke()

    // Блюдце.
    cream.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: cx - size * 0.325,
        y: size * 0.215,
        width: size * 0.65,
        height: size * 0.085
    )).fill()

    // Тело чашки: слегка сужающееся книзу, скруглённое.
    let bodyRect = NSRect(
        x: cx - size * 0.205,
        y: size * 0.285,
        width: size * 0.41,
        height: size * 0.30
    )
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: size * 0.05, yRadius: size * 0.05)
    body.fill()

    // Кромка чашки: эллипс изнутри, затем тёмный кофе внутри него.
    cream.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: cx - size * 0.205,
        y: size * 0.505,
        width: size * 0.41,
        height: size * 0.105
    )).fill()

    coffee.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: cx - size * 0.172,
        y: size * 0.535,
        width: size * 0.344,
        height: size * 0.062
    )).fill()

    // Пар: три коротких штриха над чашкой.
    cream.withAlphaComponent(0.75).setStroke()
    for (offset, height) in [(-0.09, 0.11), (0.0, 0.15), (0.09, 0.11)] {
        let x = cx + size * CGFloat(offset)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: size * 0.665))
        path.curve(
            to: NSPoint(x: x, y: size * (0.665 + CGFloat(height))),
            controlPoint1: NSPoint(x: x - size * 0.035, y: size * (0.70 + CGFloat(height) * 0.3)),
            controlPoint2: NSPoint(x: x + size * 0.035, y: size * (0.72 + CGFloat(height) * 0.5))
        )
        path.lineWidth = size * 0.022
        path.lineCapStyle = .round
        path.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MagicCaffeinate.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(pixels: variant.pixels)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: iconsetURL.appendingPathComponent("\(variant.name).png"))
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil exited with \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}
try? FileManager.default.removeItem(at: iconsetURL)
print("✓ \(outputURL.path)")
