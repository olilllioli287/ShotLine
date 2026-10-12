// Draws the ShotLine app icon: two screenshots in crisp glass frames, held
// by aluminium clips on a thin line, over a teal gradient, with a green
// checkmark badge for keeping a capture.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func shadow(_ alpha: CGFloat, blur: CGFloat, y: CGFloat) {
    let s = NSShadow()
    s.shadowColor = color(20, 24, 48, alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

// Body, following the macOS icon grid: 824pt square, 100pt margin.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
shadow(0.30, blur: 26, y: -12)
color(200, 210, 240).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
NSGradient(colors: [color(40, 160, 150), color(70, 190, 170), color(170, 230, 200)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -60)
// Soft light from the top.
NSGradient(colors: [color(255, 255, 255, 0.35), color(255, 255, 255, 0)])!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// The line
let left = NSPoint(x: 60, y: 700), right = NSPoint(x: 964, y: 700)
let control = NSPoint(x: 512, y: 590)
func lineY(_ x: CGFloat) -> CGFloat {
    let t = (x - left.x) / (right.x - left.x)
    return (1 - t) * (1 - t) * left.y + 2 * (1 - t) * t * control.y + t * t * right.y
}
func linePath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: left)
    p.curve(to: right,
            controlPoint1: NSPoint(x: left.x + (control.x - left.x) * 2 / 3, y: left.y + (control.y - left.y) * 2 / 3),
            controlPoint2: NSPoint(x: right.x + (control.x - right.x) * 2 / 3, y: right.y + (control.y - right.y) * 2 / 3))
    return p
}
ctx.saveGState()
shadow(0.25, blur: 8, y: -5)
let line = linePath()
line.lineWidth = 9
color(110, 116, 140).setStroke()
line.stroke()
ctx.restoreGState()
let highlight = linePath()
highlight.lineWidth = 3
highlight.transform(using: AffineTransform(translationByX: 0, byY: 2))
color(255, 255, 255, 0.55).setStroke()
highlight.stroke()

// A screenshot in a glass frame, hanging from a clip.
func hang(centerX: CGFloat, width: CGFloat, height: CGFloat, angle: CGFloat, content: (NSRect) -> Void) {
    let top = lineY(centerX) + 34
    ctx.saveGState()
    ctx.translateBy(x: centerX, y: top)
    ctx.rotate(by: angle * .pi / 180)

    let radius: CGFloat = 64, inset: CGFloat = 18
    let frame = NSRect(x: -width / 2, y: -height, width: width, height: height)
    let framePath = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

    // Glass: translucent white body, soft shadow, top-lit edge.
    ctx.saveGState()
    shadow(0.28, blur: 40, y: -22)
    color(255, 255, 255, 0.42).setFill()
    framePath.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(255, 255, 255, 0.30), color(255, 255, 255, 0.05)])!
        .draw(in: framePath, angle: -90)

    let photoRect = frame.insetBy(dx: inset, dy: inset)
    let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: radius - inset, yRadius: radius - inset)
    ctx.saveGState()
    photoPath.addClip()
    content(photoRect)
    ctx.restoreGState()

    // Top-lit edge: a thin ring, brighter at the top.
    ctx.saveGState()
    let ring = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ring.append(NSBezierPath(roundedRect: frame.insetBy(dx: 4, dy: 4), xRadius: radius - 4, yRadius: radius - 4))
    ring.windingRule = .evenOdd
    ring.addClip()
    NSGradient(colors: [color(255, 255, 255, 0.95), color(255, 255, 255, 0.30)])!.draw(in: frame, angle: -90)
    ctx.restoreGState()

    // Aluminium clip
    let clip = NSRect(x: -15, y: -58, width: 30, height: 86)
    let clipPath = NSBezierPath(roundedRect: clip, xRadius: 11, yRadius: 11)
    ctx.saveGState()
    shadow(0.35, blur: 8, y: -5)
    color(200, 200, 205).setFill()
    clipPath.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(170, 172, 180), color(240, 241, 245), color(212, 214, 220), color(150, 152, 160)],
               atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)!
        .draw(in: clipPath, angle: 0)
    color(40, 40, 50, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: -9, y: -6, width: 18, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
    clipPath.lineWidth = 2
    color(255, 255, 255, 0.7).setStroke()
    clipPath.stroke()

    ctx.restoreGState()
}

// Left: a small app window.
hang(centerX: 330, width: 340, height: 400, angle: 3) { r in
    color(248, 249, 252).setFill(); r.fill()
    let bar = NSRect(x: r.minX, y: r.maxY - 56, width: r.width, height: 56)
    color(232, 234, 240).setFill(); bar.fill()
    for (i, c) in [color(255, 95, 87), color(254, 188, 46), color(40, 200, 64)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 26 + CGFloat(i) * 30, y: bar.midY - 9, width: 18, height: 18)).fill()
    }
    color(100, 120, 255).setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX + 26, y: bar.minY - 70, width: r.width * 0.55, height: 26), xRadius: 8, yRadius: 8).fill()
    color(200, 204, 216).setFill()
    for i in 0..<5 {
        let w = r.width * [0.78, 0.66, 0.72, 0.5, 0.62][i]
        NSBezierPath(roundedRect: NSRect(x: r.minX + 26, y: bar.minY - 120 - CGFloat(i) * 38, width: w, height: 16), xRadius: 8, yRadius: 8).fill()
    }
}

// Right: a sunset photo.
hang(centerX: 695, width: 320, height: 270, angle: -3) { r in
    NSGradient(colors: [color(255, 150, 90), color(255, 110, 130), color(120, 90, 200)])!.draw(in: r, angle: 90)
    color(255, 230, 160).setFill()
    NSBezierPath(ovalIn: NSRect(x: r.midX - 40, y: r.minY + 60, width: 80, height: 80)).fill()
    let hills = NSBezierPath()
    hills.move(to: NSPoint(x: r.minX, y: r.minY + 70))
    hills.curve(to: NSPoint(x: r.maxX, y: r.minY + 50), controlPoint1: NSPoint(x: r.minX + r.width * 0.3, y: r.minY + 130),
                controlPoint2: NSPoint(x: r.minX + r.width * 0.6, y: r.minY + 10))
    hills.line(to: NSPoint(x: r.maxX, y: r.minY)); hills.line(to: NSPoint(x: r.minX, y: r.minY)); hills.close()
    color(70, 50, 130).setFill(); hills.fill()
}
ctx.restoreGState()

// Checkmark badge in the bottom right.
let badge = NSRect(x: 650, y: 150, width: 220, height: 220)
ctx.saveGState()
shadow(0.30, blur: 20, y: -10)
color(52, 199, 89).setFill()
NSBezierPath(ovalIn: badge).fill()
ctx.restoreGState()
let check = NSBezierPath()
check.move(to: NSPoint(x: badge.minX + 58, y: badge.midY + 2))
check.line(to: NSPoint(x: badge.minX + 96, y: badge.midY - 38))
check.line(to: NSPoint(x: badge.maxX - 52, y: badge.midY + 44))
check.lineWidth = 26
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

// Top-lit rim on the icon body.
shape.lineWidth = 4
ctx.saveGState()
shape.addClip()
color(255, 255, 255, 0.35).setStroke()
shape.stroke()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
