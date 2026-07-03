#!/usr/bin/env swift
// Generates a macOS app icon: blue rounded-rect with white fan symbol
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetPath = "\(outputDir)/AppIcon.iconset"
let icnsPath = "\(outputDir)/AppIcon.icns"

try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for (baseSize, scale, name) in sizes {
    let px = baseSize * scale
    let sz = CGFloat(px)

    let img = NSImage(size: NSSize(width: sz, height: sz))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded rect background — Apple blue gradient
    let cornerRadius = sz * 0.22
    let rect = CGRect(x: 0, y: 0, width: sz, height: sz)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Gradient: top = lighter blue, bottom = darker blue
    let colors = [
        CGColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1.0),
    ]
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors as CFArray,
                               locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: sz/2, y: sz),
                           end: CGPoint(x: sz/2, y: 0),
                           options: [])
    ctx.restoreGState()

    // Fan blades (3 curved blades)
    let center = CGPoint(x: sz/2, y: sz/2)
    let bladeLen = sz * 0.28
    let bladeWidth = sz * 0.11

    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))

    for angle in stride(from: 0.0, to: 360.0, by: 120.0) {
        let rad = angle * .pi / 180.0
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(rad))

        // Blade shape: teardrop
        let bladePath = CGMutablePath()
        bladePath.move(to: CGPoint(x: 0, y: bladeWidth * 0.3))
        bladePath.addQuadCurve(to: CGPoint(x: bladeLen, y: 0),
                                control: CGPoint(x: bladeLen * 0.5, y: bladeWidth))
        bladePath.addQuadCurve(to: CGPoint(x: 0, y: -bladeWidth * 0.3),
                                control: CGPoint(x: bladeLen * 0.5, y: -bladeWidth))
        bladePath.closeSubpath()
        ctx.addPath(bladePath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Center hub
    let hubR = sz * 0.06
    ctx.fillEllipse(in: CGRect(x: center.x - hubR, y: center.y - hubR,
                                width: hubR * 2, height: hubR * 2))
    ctx.restoreGState()

    img.unlockFocus()

    // Save as PNG
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }

    try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}

// Convert to icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try? task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✅ App icon generated: \(icnsPath)")
    // Clean up iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)
} else {
    print("❌ iconutil failed")
}
