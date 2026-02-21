#!/usr/bin/env swift
// Generates NexusCommand app icon as .iconset PNGs
// A bold "N" over a deep gradient with a command-key inspired border accent

import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Rounded rect path
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.01, dy: size * 0.01),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)

    // Background gradient: deep navy to electric indigo
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1.0),  // Deep navy
        CGColor(red: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),  // Dark indigo
        CGColor(red: 0.30, green: 0.15, blue: 0.55, alpha: 1.0),  // Electric purple
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.5, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // Subtle inner glow ring
    ctx.saveGState()
    let glowInset = size * 0.06
    let innerPath = CGPath(roundedRect: rect.insetBy(dx: glowInset, dy: glowInset),
                           cornerWidth: cornerRadius - glowInset,
                           cornerHeight: cornerRadius - glowInset,
                           transform: nil)
    ctx.addPath(innerPath)
    ctx.setStrokeColor(CGColor(red: 0.5, green: 0.4, blue: 1.0, alpha: 0.3))
    ctx.setLineWidth(size * 0.015)
    ctx.strokePath()
    ctx.restoreGState()

    // Command symbol (⌘) as subtle background watermark
    ctx.saveGState()
    let cmdFont = NSFont.systemFont(ofSize: size * 0.55, weight: .ultraLight)
    let cmdString = "⌘" as NSString
    let cmdAttrs: [NSAttributedString.Key: Any] = [
        .font: cmdFont,
        .foregroundColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.06)
    ]
    let cmdSize = cmdString.size(withAttributes: cmdAttrs)
    let cmdPoint = NSPoint(x: (size - cmdSize.width) / 2 + size * 0.15,
                           y: (size - cmdSize.height) / 2 - size * 0.15)
    cmdString.draw(at: cmdPoint, withAttributes: cmdAttrs)
    ctx.restoreGState()

    // Main "N" letter — bold, geometric
    ctx.saveGState()
    let fontSize = size * 0.52
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let nString = "N" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = nString.size(withAttributes: attrs)
    let textPoint = NSPoint(x: (size - textSize.width) / 2,
                            y: (size - textSize.height) / 2 - size * 0.02)
    nString.draw(at: textPoint, withAttributes: attrs)
    ctx.restoreGState()

    // Small accent dot — electric cyan, bottom-right
    ctx.saveGState()
    let dotSize = size * 0.08
    let dotX = size * 0.72
    let dotY = size * 0.18
    let dotRect = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
    ctx.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.9))
    ctx.fillEllipse(in: dotRect)

    // Dot glow
    ctx.setShadow(offset: .zero, blur: size * 0.04,
                  color: CGColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.6))
    ctx.fillEllipse(in: dotRect)
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String, size: Int) {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()

    guard let tiffData = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for size \(size)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved \(path)")
    } catch {
        print("Error saving \(path): \(error)")
    }
}

// Main
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetDir = "\(outputDir)/Icon.iconset"

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let masterIcon = drawIcon(size: 1024)

// All required iconset sizes
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    savePNG(masterIcon, to: "\(iconsetDir)/\(entry.name).png", size: entry.size)
}

print("Iconset created at \(iconsetDir)")
print("Run: iconutil -c icns \(iconsetDir)")
