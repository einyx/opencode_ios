#!/usr/bin/env swift
// Render App Store creative images from the existing icon and real UI captures.
// Usage: swift scripts/render_store_creatives.swift --chat PATH --workspace PATH --output DIR
import AppKit
import Foundation

enum RenderError: Error { case missingArgument(String), unreadableImage(String), bitmap, png }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
func argument(_ name: String) throws -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        throw RenderError.missingArgument(name)
    }
    return arguments[index + 1]
}
func load(_ path: String) throws -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else { throw RenderError.unreadableImage(path) }
    return image
}
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let ivory = color(0xFAF9F5)
let ink = color(0x292823)
let secondary = color(0x73716A)

struct Artwork {
    let height: CGFloat

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x, y: self.height - y - height, width: width, height: height)
    }

    func text(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
              size: CGFloat, weight: NSFont.Weight = .regular, serif: Bool = false,
              foreground: NSColor = ink) {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = serif ? NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base : base
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = size * 0.08
        (string as NSString).draw(in: rect(x, y, width, height), withAttributes: [
            .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
        ])
    }

    func image(_ image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
               radius: CGFloat, frame: CGFloat = 0) {
        let bounds = rect(x, y, width, height)
        if frame > 0 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = ink.withAlphaComponent(0.14)
            shadow.shadowBlurRadius = 42
            shadow.shadowOffset = NSSize(width: 0, height: -18)
            shadow.set()
            ink.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: -frame, dy: -frame),
                         xRadius: radius + frame, yRadius: radius + frame).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func render(width: Int, height: Int, output: URL, draw: (Artwork) -> Void) throws {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let bitmapContext = CGContext(data: nil, width: width, height: height,
                                        bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw RenderError.bitmap }
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    ivory.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw(Artwork(height: CGFloat(height)))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = bitmapContext.makeImage() else { throw RenderError.bitmap }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.png }
    try data.write(to: output, options: .atomic)
    print("Rendered \(output.lastPathComponent): \(width)x\(height), opaque RGB")
}

do {
    let chat = try load(argument("--chat"))
    let workspace = try load(argument("--workspace"))
    let icon = try load(root.appendingPathComponent("OpenCodeClient/OpenCodeClient/Assets.xcassets/AppIcon.appiconset/AppIcon.png").path)
    let output = URL(fileURLWithPath: try argument("--output"), isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    try render(width: 3840, height: 1646, output: output.appendingPathComponent("opencodex-header.png")) { art in
        art.image(icon, x: 240, y: 260, width: 156, height: 156, radius: 38)
        art.text("OpenCodeX", x: 442, y: 281, width: 1240, height: 140, size: 100, serif: true)
        art.text("Your coding agents.\nWithin reach.", x: 240, y: 568, width: 1920, height: 440,
                 size: 166, weight: .semibold)
        art.text("Chat. Follow tools. Review changes.", x: 250, y: 1120, width: 1880, height: 140,
                 size: 72, foreground: secondary)
        art.image(workspace, x: 2200, y: 220, width: 900, height: 1200, radius: 44, frame: 12)
        art.image(chat, x: 2990, y: 344, width: 500, height: 1087.1, radius: 74, frame: 12)
    }

    try render(width: 1920, height: 1280, output: output.appendingPathComponent("opencodex-search.png")) { art in
        art.image(icon, x: 130, y: 180, width: 116, height: 116, radius: 28)
        art.text("OpenCodeX", x: 278, y: 200, width: 850, height: 100, size: 64, serif: true)
        art.text("Your coding agents.\nWithin reach.", x: 130, y: 430, width: 1000, height: 280,
                 size: 94, weight: .semibold)
        art.text("Chat. Follow tools.\nReview changes.", x: 138, y: 820, width: 900, height: 180,
                 size: 48, foreground: secondary)
        art.image(chat, x: 1230, y: 110, width: 480, height: 1043.6, radius: 68, frame: 10)
    }
} catch {
    fputs("Creative rendering failed: \(error)\n", stderr)
    exit(1)
}
