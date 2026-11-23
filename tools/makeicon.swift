// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

// Draws SecondBar.icns: a menu bar strip above a panel of icons, i.e. what the
// app does. Run once; build.sh only regenerates when the iconset is missing.
//
//     swift tools/makeicon.swift Assets
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
// Apple's artwork box for a 1024 canvas: 824x824 centred, corner radius 185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(into ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Body, with a soft vertical gradient.
    let shape = roundedPath(body, bodyRadius)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x5A6478), color(0x1C2230)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY),
                           options: [])
    // A faint highlight along the top edge keeps it from looking flat.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.maxY - 300),
                           options: [])
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.16))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // The menu bar: a light strip across the top with three status dots.
    let bar = CGRect(x: 165, y: 730, width: 694, height: 96)
    ctx.addPath(roundedPath(bar, 48))
    ctx.setFillColor(color(0xF2F4F8, 0.95))
    ctx.fillPath()
    for (index, cx) in [742.0, 795.0, 848.0].enumerated() {
        let r: CGFloat = index == 2 ? 15 : 12
        ctx.addEllipse(in: CGRect(x: cx - r, y: bar.midY - r, width: r * 2, height: r * 2))
        ctx.setFillColor(color(0x2B3242, index == 2 ? 0.85 : 0.45))
        ctx.fillPath()
    }
    // A divider, as on a real bar: these dots are the folded side.
    ctx.move(to: CGPoint(x: 706, y: bar.minY + 22))
    ctx.addLine(to: CGPoint(x: 706, y: bar.maxY - 22))
    ctx.setStrokeColor(color(0x2B3242, 0.22))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // The second bar: the panel the arrow opens, holding the folded icons.
    let panel = CGRect(x: 165, y: 168, width: 694, height: 500)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 34, color: color(0x000000, 0.35))
    ctx.addPath(roundedPath(panel, 68))
    ctx.setFillColor(color(0xF5F7FA, 0.97))
    ctx.fillPath()
    ctx.restoreGState()

    let columns: [CGFloat] = [292, 512, 732]
    let rows: [CGFloat] = [512, 316]
    for (rowIndex, cy) in rows.enumerated() {
        for (columnIndex, cx) in columns.enumerated() {
            // One icon in accent colour, so the panel reads as "your icons".
            let accented = rowIndex == 0 && columnIndex == 1
            let r: CGFloat = 40
            ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.setFillColor(accented ? color(0x3B82F6) : color(0x39404F))
            ctx.fillPath()
        }
    }
}

func render(scaleTo size: Int) -> CGImage? {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx else { return nil }
    // Draw at full resolution, then let the context downsample once.
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(into: ctx)
    return ctx.makeImage()
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets"
let iconset = URL(fileURLWithPath: output).appendingPathComponent("SecondBar.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects, as (points, scale).
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                              (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in variants {
    let pixels = points * scale
    guard let image = render(scaleTo: pixels) else { continue }
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let url = iconset.appendingPathComponent(name)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: points, height: points)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
print("wrote \(iconset.path)")
