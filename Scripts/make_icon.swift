// Generates MoleUX's app icon.
//
// Drawn in code rather than shipped as binary art so the icon stays reviewable
// and reproducible: tweak a number here, re-run, get a new .icns.
//
//   swift Scripts/make_icon.swift
//
// Concept: a spade sunk into layered soil. "Dig into your disk" is the product
// metaphor, and a spade is its universal symbol — it stays a clean silhouette at
// 16pt, where the burrow shapes I tried first turned into an eye, a tadpole and
// a slingshot in turn. Concentric forms read as eyes; tapered ones read as
// organisms. A tool reads as a tool.

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

struct RGBA {
    let r, g, b, a: CGFloat
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }
    var components: [CGFloat] { [r, g, b, a] }
}

/// Soil in section: sunlit topsoil at the surface, cold deep earth at the bottom.
let soilTop = RGBA(0x5E3C21)
let soilBottom = RGBA(0x120A05)

/// Strata seams, as fractions of the plate height from its bottom, with weight.
/// Uneven spacing and low contrast: regular hard lines read as planking, not soil.
let strata: [(fraction: CGFloat, thickness: CGFloat, alpha: CGFloat)] = [
    (0.235, 13, 0.16),
    (0.615, 8, 0.11),
]

/// The spade, two-tone: a bright blade carries the silhouette, a warmer shaft
/// keeps it from reading as one flat cut-out.
let bladeLight = RGBA(0xFFF0D2)
let bladeWarm = RGBA(0xE9A63F)
let shaftLight = RGBA(0xD98F33)
let shaftWarm = RGBA(0xA96420)
/// Tilted a little so it reads as sunk into the ground, not diagrammed.
let spadeTilt: CGFloat = -11 * .pi / 180
/// The spade was drawn against Apple's 824pt inset plate; at full bleed it has
/// to grow by the same ratio to keep its weight on the plate.
let spadeScale: CGFloat = 1024 / 824

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

/// The spade as three separate shapes. Kept separate on purpose: merged into one
/// CGPath, subpaths wound in opposite directions punch holes in each other where
/// they overlap under the nonzero fill rule.
func spadeParts() -> (blade: CGPath, socket: CGPath, shaft: CGPath) {
    let blade = CGMutablePath()
    let halfWidth: CGFloat = 178
    let shoulderY: CGFloat = 96
    let corner: CGFloat = 26

    // Tip up the right flank, square across the shoulders, back down the left.
    // A flat shoulder with rounded corners is what makes this a spade; the
    // dipped shoulder line I tried first pinched into barbs at both ends.
    blade.move(to: CGPoint(x: 0, y: -292))
    blade.addCurve(
        to: CGPoint(x: 172, y: -46),
        control1: CGPoint(x: 88, y: -264),
        control2: CGPoint(x: 150, y: -164)
    )
    blade.addLine(to: CGPoint(x: halfWidth, y: shoulderY - corner))
    blade.addArc(
        tangent1End: CGPoint(x: halfWidth, y: shoulderY),
        tangent2End: CGPoint(x: halfWidth - corner, y: shoulderY),
        radius: corner
    )
    blade.addLine(to: CGPoint(x: -halfWidth + corner, y: shoulderY))
    blade.addArc(
        tangent1End: CGPoint(x: -halfWidth, y: shoulderY),
        tangent2End: CGPoint(x: -halfWidth, y: shoulderY - corner),
        radius: corner
    )
    blade.addLine(to: CGPoint(x: -172, y: -46))
    blade.addCurve(
        to: CGPoint(x: 0, y: -292),
        control1: CGPoint(x: -150, y: -164),
        control2: CGPoint(x: -88, y: -264)
    )
    blade.closeSubpath()

    // Socket: the collar joining blade to shaft, overlapping both so they merge.
    let socket = CGMutablePath()
    socket.move(to: CGPoint(x: -76, y: 82))
    socket.addLine(to: CGPoint(x: 76, y: 82))
    socket.addLine(to: CGPoint(x: 50, y: 244))
    socket.addLine(to: CGPoint(x: -50, y: 244))
    socket.closeSubpath()

    let shaft = CGPath(
        roundedRect: CGRect(x: -45, y: 226, width: 90, height: 286),
        cornerWidth: 30, cornerHeight: 30, transform: nil
    )

    return (blade, socket, shaft)
}

/// The spade positioned and tilted on the plate.
func placedSpade(scale: CGFloat) -> [CGPath] {
    var transform = CGAffineTransform(scaleX: scale, y: scale)
        .translatedBy(x: 512, y: 470)
        .rotated(by: spadeTilt)
        .scaledBy(x: spadeScale, y: spadeScale)
    let parts = spadeParts()
    return [parts.blade, parts.socket, parts.shaft].compactMap { $0.copy(using: &transform) }
}

func drawIcon(into ctx: CGContext, size: Int) {
    let dimension = CGFloat(size)

    ctx.saveGState()
    ctx.scaleBy(x: dimension / canvas, y: dimension / canvas)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let plate = platePath(center: center, radius: plateRadius)
    let plateHeight = canvas - plateInset * 2

    ctx.addPath(plate)
    ctx.clip()

    ctx.drawLinearGradient(
        gradient(soilTop, soilBottom),
        start: CGPoint(x: 0, y: canvas - plateInset),
        end: CGPoint(x: 0, y: plateInset),
        options: []
    )

    // Strata: dark seams only. A lit edge above each one turns soil into planking.
    for seam in strata {
        let y = plateInset + plateHeight * seam.fraction
        ctx.setFillColor(CGColor(red: 0.05, green: 0.02, blue: 0, alpha: seam.alpha))
        ctx.fill(CGRect(x: plateInset, y: y, width: plateHeight, height: seam.thickness))
    }
    ctx.restoreGState()

    // Everything below is in device space so the masks line up 1:1 with pixels.
    ctx.saveGState()
    ctx.addPath({
        let p = CGMutablePath()
        let t = CGAffineTransform(scaleX: dimension / canvas, y: dimension / canvas)
        p.addPath(platePath(center: center, radius: plateRadius), transform: t)
        return p
    }())
    ctx.clip()

    let parts = placedSpade(scale: dimension / canvas)

    // Shadow cast into the soil. Drawn inside a transparency layer so the three
    // parts cast one shadow between them instead of shadowing each other.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 10 * dimension / canvas, height: -14 * dimension / canvas),
        blur: 30 * dimension / canvas,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    for part in parts {
        ctx.addPath(part)
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // The spade. Each part is clipped and filled on its own — merging them into
    // one path would reintroduce the winding hole.
    let g = dimension / canvas
    // parts is [blade, socket, shaft]; the blade gets the bright ramp.
    let ramps = [(bladeLight, bladeWarm), (shaftLight, shaftWarm), (shaftLight, shaftWarm)]
    for (part, ramp) in zip(parts, ramps) {
        ctx.saveGState()
        ctx.addPath(part)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient(ramp.0, ramp.1),
            start: CGPoint(x: 300 * g, y: 200 * g),
            end: CGPoint(x: 760 * g, y: 820 * g),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }

    // Overall top-down sheen, keeps the plate from reading flat.
    let s = dimension / canvas
    ctx.drawLinearGradient(
        gradient(RGBA(0xFFFFFF, 0.09), RGBA(0xFFFFFF, 0)),
        start: CGPoint(x: 0, y: (canvas - plateInset) * s),
        end: CGPoint(x: 0, y: canvas * 0.55 * s),
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
