// Draws the app icon (a white cube on a violet plate) and writes the PNG sizes
// iconutil needs.
// Usage: swift tools/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.42, green: 0.27, blue: 0.93, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.60, green: 0.40, blue: 1.00, alpha: 1),
        CGColor(red: 0.33, green: 0.20, blue: 0.85, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "cube.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let ratio = symbol.size.width / symbol.size.height
    let h: CGFloat = 470, w = h * ratio
    let rect = CGRect(x: 512 - w / 2, y: 512 - h / 2 - 6, width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    symbol.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
