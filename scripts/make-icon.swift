// Renders the app icon master (1024px). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt plate centred in a 1024pt canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

NSGradient(colors: [
    NSColor(srgbRed: 0.24, green: 0.56, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.29, green: 0.25, blue: 0.86, alpha: 1),
])!.draw(in: shape, angle: -90)

// Soft top highlight.
ctx.saveGState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
ctx.restoreGState()

func symbol(_ name: String, points: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func draw(_ image: NSImage, centredAt centre: CGPoint) {
    let s = image.size
    image.draw(in: CGRect(x: centre.x - s.width / 2, y: centre.y - s.height / 2, width: s.width, height: s.height))
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24,
              color: NSColor.black.withAlphaComponent(0.25).cgColor)
draw(symbol("shield.fill", points: 470, color: .white), centredAt: CGPoint(x: 512, y: 505))
ctx.restoreGState()
draw(symbol("arrow.left.arrow.right", points: 200,
            color: NSColor(srgbRed: 0.27, green: 0.38, blue: 0.93, alpha: 1)),
     centredAt: CGPoint(x: 512, y: 530))

try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
