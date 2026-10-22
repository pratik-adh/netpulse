// Draws Resources/icon_1024.png: a speed gauge with a pulse line through it,
// on the app's own brand gradient, inside a macOS-standard 824pt squircle.
//
//   swift MakeIcon.swift <output.png>
//
import AppKit
import CoreGraphics

let side: CGFloat = 1024
let bodyInset: CGFloat = 100           // Apple's grid: 824x824 body in a 1024 canvas
let bodySide = side - bodyInset * 2
let center = CGPoint(x: side / 2, y: side / 2)

// MARK: - Shapes

/// A superellipse - |x/a|^n + |y/a|^n = 1 - which is what macOS's "continuous
/// corner" app icon shape actually is. A plain rounded rect (circular corners)
/// reads subtly wrong next to every other icon in the Dock.
func squircle(center c: CGPoint, side s: CGFloat, exponent n: CGFloat = 6.2) -> CGPath {
    let a = s / 2
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        // Parametric form of the superellipse.
        let x = a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = a * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        let p = CGPoint(x: c.x + x, y: c.y + y)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

func arc(radius: CGFloat, fromClockDegrees start: CGFloat, sweep: CGFloat) -> CGPath {
    // Clock angles: 0 = 12 o'clock, growing clockwise. CoreGraphics measures
    // counter-clockwise from 3 o'clock, hence the conversion.
    let toRadians = { (clock: CGFloat) in (90 - clock) * .pi / 180 }
    let path = CGMutablePath()
    path.addArc(center: center,
                radius: radius,
                startAngle: toRadians(start),
                endAngle: toRadians(start + sweep),
                clockwise: true)
    return path
}

func capsule(cx: CGFloat, cy: CGFloat, width w: CGFloat, height h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
           cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// MARK: - Draw

func newContext() -> CGContext {
    guard let ctx = CGContext(data: nil,
                              width: Int(side), height: Int(side),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create the bitmap context") }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

let body = squircle(center: center, side: bodySide)

// The artwork is drawn on its own transparent canvas first, then stamped into
// the final one with a shadow. Casting the shadow off a black fill *under* a
// clipped gradient instead leaves a dark antialiased fringe all the way round
// the shape - it reads as a drawn-on outline at every size.
let artwork = newContext()

artwork.saveGState()
artwork.addPath(body)
artwork.clip()

// Brand gradient: deep indigo falling into the popover's download blue and
// on into a bright cyan, corner to corner.
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0.25, 0.22, 0.66),
                                   rgb(0.14, 0.44, 0.93),
                                   rgb(0.10, 0.76, 0.88)] as CFArray,
                          locations: [0, 0.55, 1])!
artwork.drawLinearGradient(gradient,
                           start: CGPoint(x: bodyInset, y: side - bodyInset),
                           end: CGPoint(x: side - bodyInset, y: bodyInset),
                           options: [])

// A wide, faint wash from the top-left, which is where macOS's own icons take
// their light from.
let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [rgb(1, 1, 1, 0.20), rgb(1, 1, 1, 0)] as CFArray,
                           locations: [0, 1])!
artwork.drawLinearGradient(highlight,
                           start: CGPoint(x: bodyInset, y: side - bodyInset),
                           end: CGPoint(x: side * 0.62, y: side * 0.34),
                           options: [])

// The gauge: a speedometer's 270-degree sweep, open at the bottom - the same
// ring the popover uses for usage and live speed, read as a dial.
let ringRadius: CGFloat = 296
let ringWidth: CGFloat = 64

artwork.setLineCap(.round)
artwork.setLineWidth(ringWidth)

artwork.addPath(arc(radius: ringRadius, fromClockDegrees: -135, sweep: 270))
artwork.setStrokeColor(rgb(1, 1, 1, 0.24))
artwork.strokePath()

artwork.addPath(arc(radius: ringRadius, fromClockDegrees: -135, sweep: 196))
artwork.setStrokeColor(rgb(1, 1, 1, 0.97))
artwork.strokePath()

// The pulse: one heartbeat-style spike across the middle of the dial - live
// traffic, and the app's name. Kept thick, with round joins, so it still
// reads at the 16pt icon size.
let pulse = CGMutablePath()
let baseline = center.y - 6
let points: [CGPoint] = [
    CGPoint(x: center.x - 196, y: baseline),
    CGPoint(x: center.x - 92,  y: baseline),
    CGPoint(x: center.x - 44,  y: baseline + 138),
    CGPoint(x: center.x + 30,  y: baseline - 150),
    CGPoint(x: center.x + 86,  y: baseline),
    CGPoint(x: center.x + 196, y: baseline),
]
pulse.addLines(between: points)
artwork.addPath(pulse)
artwork.setLineWidth(52)
artwork.setLineJoin(.round)
artwork.setLineCap(.round)
artwork.setStrokeColor(rgb(1, 1, 1, 0.97))
artwork.strokePath()
artwork.restoreGState()

guard let artworkImage = artwork.makeImage() else { fatalError("could not snapshot the artwork") }

// Soft contact shadow, so the icon sits in the Dock and in Finder like a
// system one instead of floating flat.
let ctx = newContext()
ctx.setShadow(offset: CGSize(width: 0, height: -8),
              blur: 22,
              color: rgb(0.05, 0.12, 0.20, 0.20))
ctx.draw(artworkImage, in: CGRect(x: 0, y: 0, width: side, height: side))

// MARK: - Write

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let image = ctx.makeImage() else { fatalError("could not snapshot the context") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: side, height: side)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
