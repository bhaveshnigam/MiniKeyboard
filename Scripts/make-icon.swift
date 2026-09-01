#!/usr/bin/env swift
// Renders MiniKeyboard.icns.
//
// The mark is the object the app configures: a cream keycap with a brass
// knob ring, on graphite. Drawn at every size macOS asks for.

import AppKit
import CoreGraphics

let graphiteTop  = NSColor(srgbRed: 0.180, green: 0.192, blue: 0.216, alpha: 1)
let graphiteBot  = NSColor(srgbRed: 0.086, green: 0.094, blue: 0.114, alpha: 1)
let capFace      = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.890, alpha: 1)
let capSkirt     = NSColor(srgbRed: 0.749, green: 0.733, blue: 0.702, alpha: 1)
let brass        = NSColor(srgbRed: 1.000, green: 0.714, blue: 0.153, alpha: 1)

func drawIcon(size s: CGFloat, into ctx: CGContext) {
    let r = s * 0.2237                       // macOS corner radius ratio
    let body = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
                          colors: [graphiteTop.cgColor, graphiteBot.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: 0), options: [])

    // Keycap, sitting slightly above centre.
    let capW = s * 0.46, capH = s * 0.40
    let capX = s * 0.16, capY = s * 0.40
    let skirtR = s * 0.075, faceR = s * 0.055

    ctx.setFillColor(capSkirt.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: capX, y: capY - s * 0.055,
                                           width: capW, height: capH),
                       cornerWidth: skirtR, cornerHeight: skirtR, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(capFace.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: capX + s * 0.030, y: capY,
                                           width: capW - s * 0.060,
                                           height: capH - s * 0.055),
                       cornerWidth: faceR, cornerHeight: faceR, transform: nil))
    ctx.fillPath()

    // Knob: a brass ring with a position tick, overlapping the cap's corner.
    let knobR = s * 0.175
    let cx = s * 0.705, cy = s * 0.325
    ctx.setLineWidth(s * 0.055)
    ctx.setStrokeColor(brass.cgColor)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: knobR,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Tick angled off vertical, so the mark reads as a dial mid-turn rather
    // than as a power symbol.
    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.050)
    let tick = CGFloat.pi / 3.4          // ~53 degrees from vertical
    let inner = knobR * 0.28, outer = knobR * 0.94
    ctx.move(to: CGPoint(x: cx + sin(tick) * inner, y: cy + cos(tick) * inner))
    ctx.addLine(to: CGPoint(x: cx + sin(tick) * outer, y: cy + cos(tick) * outer))
    ctx.strokePath()

    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    drawIcon(size: CGFloat(size), into: gctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MiniKeyboard.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// name -> pixel size
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    try! png(size: px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("Wrote \(variants.count) images to \(out)")
