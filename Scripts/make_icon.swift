// Generates MoleUX's app icon.
//
// Drawn in code rather than shipped as binary art so the icon stays reviewable
// and reproducible: tweak a number here, re-run, get a new .icns.
//
//   swift Scripts/make_icon.swift Assets
//
// Concept: a burrow seen head-on. Concentric bands recede along a diagonal and
// darken inward, so the eye reads depth — a mole's tunnel.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Design constants (1024pt design space)

let canvas: CGFloat = 1024

/// The art is a full-bleed opaque square, and the system rounds it.
///
/// macOS 26 reshapes every app icon. Art that draws its own rounded plate is
/// measured against the expected silhouette, and anything that misses — this
/// icon's hand-rolled superellipse did — is inset onto a light placeholder
/// plate, which reads as a double frame. Verified by A/B: swapping a shipping
/// app's .icns into this bundle rendered clean, so the bundle was fine and the
/// pixels were not; filling the canvas edge to edge then rendered clean too,
/// with the system supplying the mask, rim light and shadow.
///
/// The cost is macOS 14–15, which do no reshaping and will draw this with square
/// corners. Chosen deliberately: a hard corner on older systems is a blemish,
/// the double frame on current ones looks broken.
let plateInset: CGFloat = 0
let plateRadius = canvas / 2

/// The bands were proportioned against Apple's 824pt inset plate. At full bleed
/// the visible area is the whole canvas, so the art grows by the same ratio to
/// keep its weight.
let artScale: CGFloat = 1024 / 824

struct RGBA {
    let r, g, b, a: CGFloat
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }
    var components: [CGFloat] { [r, g, b, a] }
    var cgColor: CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

/// Soil, lit from above: warm espresso plate, amber tunnel mouth.
let plateTop = RGBA(0x3A2C20)
let plateBottom = RGBA(0x140D08)

/// Outermost first. Each band is painted over the previous one, so the tunnel
/// darkens inward the way a real burrow does.
let tunnelBands: [(radius: CGFloat, color: RGBA)] = [
    (300, RGBA(0xF5A83F)),
    (236, RGBA(0xD1761D)),
    (176, RGBA(0x8E4715)),
    (122, RGBA(0x4C240D)),
    (74,  RGBA(0x1C0D06)),
]

/// Each band steps this far toward the upper right, bending the tunnel.
let bandDrift = CGSize(width: 17, height: 15)

/// Light catching the lower-left lip of the tunnel mouth.
let rimLight = RGBA(0xFFD9A0, 0.5)

// MARK: - Geometry

/// The plate is a plain square — see the note on `plateInset`. Rounding happens
/// in the system compositor, not here.
func platePath(center: CGPoint, radius: CGFloat) -> CGPath {
    CGPath(
        rect: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
        transform: nil
    )
}

func gradient(_ from: RGBA, _ to: RGBA) -> CGGradient {
    CGGradient(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        colorComponents: from.components + to.components,
        locations: [0, 1],
        count: 2
    )!
}

// MARK: - Drawing

func drawIcon(into ctx: CGContext, size: Int) {
    let dimension = CGFloat(size)

    ctx.saveGState()
    ctx.scaleBy(x: dimension / canvas, y: dimension / canvas)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    ctx.addPath(platePath(center: center, radius: plateRadius))
    ctx.clip()

    // Soil.
    ctx.drawLinearGradient(
        gradient(plateTop, plateBottom),
        start: CGPoint(x: 0, y: canvas - plateInset),
        end: CGPoint(x: 0, y: plateInset),
        options: []
    )

    // Tunnel: filled discs stacked outer-to-inner, each nudged up and right.
    for (index, band) in tunnelBands.enumerated() {
        let step = CGFloat(index)
        let radius = band.radius * artScale
        let bandCenter = CGPoint(
            x: center.x + bandDrift.width * step * artScale,
            y: center.y + bandDrift.height * step * artScale
        )
        ctx.setFillColor(band.color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: bandCenter.x - radius,
            y: bandCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    // Rim light along the tunnel mouth's lower left, where soil catches the sky.
    ctx.saveGState()
    ctx.setStrokeColor(rimLight.cgColor)
    ctx.setLineWidth(10 * artScale)
    ctx.setLineCap(.round)
    ctx.addArc(
        center: center,
        radius: (tunnelBands[0].radius - 5) * artScale,
        startAngle: .pi * 0.62,
        endAngle: .pi * 1.62,
        clockwise: false
    )
    ctx.strokePath()
    ctx.restoreGState()

    // Overall top-down sheen, keeps the plate from reading flat.
    ctx.drawLinearGradient(
        gradient(RGBA(0xFFFFFF, 0.10), RGBA(0xFFFFFF, 0)),
        start: CGPoint(x: 0, y: canvas - plateInset),
        end: CGPoint(x: 0, y: canvas * 0.52),
        options: []
    )
    ctx.restoreGState()
}

func renderPNG(size: Int, to url: URL) {
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write(Data("could not create \(size)pt context\n".utf8))
        exit(1)
    }

    drawIcon(into: ctx, size: size)

    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else {
        FileHandle.standardError.write(Data("could not encode \(size)pt png\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// MARK: - Iconset

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Assets")
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten entries `iconutil` expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    renderPNG(size: variant.pixels, to: iconset.appendingPathComponent("\(variant.name).png"))
}
print("wrote \(variants.count) images to \(iconset.path)")
