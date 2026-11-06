import AppKit
import CoreGraphics

let home = NSHomeDirectory()
let logoPath = "\(home)/Library/Application Support/Steam/steamapps/content/app_975370/depot_975371/data/art/df_logo.png"
let bgArtPath = "\(home)/Library/Application Support/Steam/steamapps/content/app_975370/depot_975371/data/art/title_background.png"

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
    
    // Outer shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.045, color: NSColor(calibratedWhite: 0, alpha: 0.65).cgColor)
    NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.09, alpha: 1.0).setFill()
    squircle.fill()
    ctx.restoreGState()
    
    // Clip to squircle
    ctx.saveGState()
    squircle.addClip()
    
    // Deep volcanic / obsidian gradient background
    let gradColors = [
        NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.11, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.09, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.06, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: s * 0.5, y: rect.maxY),
            end: CGPoint(x: s * 0.5, y: rect.minY),
            options: []
        )
    }
    
    // Optional subtle background art overlay if available
    if let bgImg = NSImage(contentsOfFile: bgArtPath),
       let bgCG = bgImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState()
        ctx.setAlpha(0.18)
        ctx.interpolationQuality = .none
        ctx.draw(bgCG, in: rect)
        ctx.restoreGState()
    }
    
    // Inner glowing rim
    let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.008, dy: s * 0.008), xRadius: cornerRadius * 0.96, yRadius: cornerRadius * 0.96)
    borderPath.lineWidth = max(1.5, s * 0.015)
    NSColor(calibratedRed: 0.85, green: 0.45, blue: 0.18, alpha: 0.65).setStroke()
    borderPath.stroke()
    
    if let logoImg = NSImage(contentsOfFile: logoPath),
       let logoCG = logoImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        // Crop the iconic Red-Bearded Dwarf head from df_logo.png (x: 112..224, y: 208..368 in top-left coords)
        let cropRect = CGRect(x: 112, y: 208, width: 112, height: 160)
        if let dwarfHeadCG = logoCG.cropping(to: cropRect) {
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.03, color: NSColor.black.cgColor)
            
            let headHeight = rect.height * 0.48
            let headWidth = headHeight * (112.0 / 160.0)
            let headRect = CGRect(
                x: (s - headWidth) * 0.5,
                y: rect.minY + rect.height * 0.43,
                width: headWidth,
                height: headHeight
            )
            ctx.draw(dwarfHeadCG, in: headRect)
            ctx.restoreGState()
        }
        
        // Draw the full "DWARF FORTRESS" logo across the bottom portion
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.02, color: NSColor.black.cgColor)
        let logoW = rect.width * 0.84
        let logoH = logoW * (373.0 / 907.0)
        let logoDrawRect = CGRect(
            x: (s - logoW) * 0.5,
            y: rect.minY + rect.height * 0.07,
            width: logoW,
            height: logoH
        )
        ctx.draw(logoCG, in: logoDrawRect)
        ctx.restoreGState()
    }
    
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
print("Generated iconset successfully!")
