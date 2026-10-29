// The app icon, drawn in the app's own palette (Panels.swift): a spectrum's blue fill and peak line under the green
// waveform of a word, on the panel's dark background. Square and opaque: iOS and macOS 26+ mask the corners
// themselves. ponytail: macOS 14/15 show the Mac's icns as a sharp square; draw rounded, transparent corners into the
// Mac's iconset if the app is ever used there.
//
//     swift scripts/make-icon.swift <out.png>   (1024 x 1024; `just icon` makes both apps' icons from it)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let s = CGFloat(size)
let space = CGColorSpaceCreateDeviceRGB()
guard
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("no context") }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a]) ?? CGColor(gray: 0, alpha: 1)
}

// Background: the app's panel, a little lighter at the top.
if let gradient = CGGradient(
    colorsSpace: space, colors: [color(0.13, 0.15, 0.20), color(0.05, 0.07, 0.09)] as CFArray,
    locations: [0, 1])
{
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
}

// Faint grid, as on the plots.
ctx.setStrokeColor(color(1, 1, 1, 0.06))
ctx.setLineWidth(4)
for i in 1..<6 {
    let y = s * CGFloat(i) / 6
    ctx.move(to: CGPoint(x: 0, y: y))
    ctx.addLine(to: CGPoint(x: s, y: y))
}
ctx.strokePath()

// Spectrum: a voice's shape (a low hump, formant bumps, a falling tail), filled blue along the bottom.
func spectrum(_ x: CGFloat) -> CGFloat {
    let f = x / s
    let hump = 0.42 * exp(-pow((f - 0.22) / 0.12, 2))
    let formants = 0.16 * exp(-pow((f - 0.45) / 0.05, 2)) + 0.11 * exp(-pow((f - 0.62) / 0.05, 2))
    return s * (0.08 + hump + formants + 0.06 * (1 - f))
}
let spectrumPath = CGMutablePath()
spectrumPath.move(to: CGPoint(x: 0, y: 0))
for x in stride(from: CGFloat(0), through: s, by: 4) { spectrumPath.addLine(to: CGPoint(x: x, y: spectrum(x))) }
spectrumPath.addLine(to: CGPoint(x: s, y: 0))
spectrumPath.closeSubpath()
ctx.addPath(spectrumPath)
ctx.setFillColor(color(0.35, 0.65, 1, 0.28))
ctx.fillPath()
let peakLine = CGMutablePath()
peakLine.move(to: CGPoint(x: 0, y: spectrum(0)))
for x in stride(from: CGFloat(0), through: s, by: 4) { peakLine.addLine(to: CGPoint(x: x, y: spectrum(x))) }
ctx.addPath(peakLine)
ctx.setStrokeColor(color(0.35, 0.65, 1))
ctx.setLineWidth(10)
ctx.setLineJoin(.round)
ctx.strokePath()

// Waveform: a word's burst, a few cycles under a smooth envelope, across the middle.
let mid = s * 0.56
let wave = CGMutablePath()
for x in stride(from: CGFloat(0), through: s, by: 2) {
    let f = x / s
    let envelope = 0.30 * exp(-pow((f - 0.5) / 0.2, 2))
    let y = mid + s * envelope * sin(f * .pi * 2 * 6.5) * (0.75 + 0.25 * sin(f * .pi * 2 * 1.7))
    if x == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
}
ctx.addPath(wave)
ctx.setStrokeColor(color(0.25, 0.73, 0.31))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

guard let image = ctx.makeImage(), CommandLine.arguments.count > 1 else {
    fatalError("usage: make-icon.swift <out.png>")
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("cannot write \(url.path)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
print(url.path)
