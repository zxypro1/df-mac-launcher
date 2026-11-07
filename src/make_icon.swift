import AppKit
import CoreGraphics

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let artworkPath = "\(scriptDir)/icon_artwork.jpg"
let iconsetDir = "/tmp/AppIcon.iconset"

try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }
    
    let padding = s * 0.08
    let rect = NSRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let cornerRadius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Outer drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.045, color: NSColor(calibratedWhite: 0, alpha: 0.65).cgColor)
    NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.06, alpha: 1.0).setFill()
    squircle.fill()
    ctx.restoreGState()
    
    // Clip to macOS squircle
    ctx.saveGState()
    squircle.addClip()
    
    if let artImg = NSImage(contentsOfFile: artworkPath),
       let artCG = artImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.interpolationQuality = .high
        ctx.draw(artCG, in: rect)
    }
    
    // Glowing inner border
    let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.008, dy: s * 0.008), xRadius: cornerRadius * 0.96, yRadius: cornerRadius * 0.96)
    borderPath.lineWidth = max(1.5, s * 0.015)
    NSColor(calibratedRed: 0.88, green: 0.48, blue: 0.18, alpha: 0.72).setStroke()
    borderPath.stroke()
    
    ctx.restoreGState()
    
    guard let outCG = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: outCG)
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    if let data = renderIcon(size: px) {
        try! data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
    }
}
print("✅ Generated iconset from original pixel artwork!")
