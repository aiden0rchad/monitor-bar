import AppKit

// Regenerate with: swift scripts/GenerateIcon.swift
let directory = URL(fileURLWithPath: ".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let card = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.62, alpha: 1).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.57, alpha: 1),
                   ending: NSColor(calibratedRed: 0.20, green: 0.64, blue: 0.83, alpha: 1))!.draw(in: card, angle: 90)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: NSRect(x: 208, y: 324, width: 608, height: 390), xRadius: 38, yRadius: 38).fill()
        NSBezierPath(rect: NSRect(x: 476, y: 234, width: 72, height: 96)).fill()
        NSBezierPath(roundedRect: NSRect(x: 378, y: 208, width: 268, height: 32), xRadius: 16, yRadius: 16).fill()
        NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 230, y: 354, width: 564, height: 336), xRadius: 20, yRadius: 20).fill()
        for (y, knob): (CGFloat, CGFloat) in [(440, 460), (524, 590), (608, 510)] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 326, y: y))
            line.line(to: NSPoint(x: 698, y: y))
            line.lineWidth = 12
            line.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.45).setStroke()
            line.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: knob - 23, y: y - 23, width: 46, height: 46)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", directory.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Resources/AppIcon.icns")
