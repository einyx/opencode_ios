#!/usr/bin/env swift
// Keep the watchOS marketing icon in sync with the iOS artwork. No downloads.
// Run with --check for a read-only pixel/size/opacity regression check.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("OpenCodeClient/OpenCodeClient/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let target = root.appendingPathComponent("OpenCodeClient/OpenCodeWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

enum IconError: Error { case unreadable, invalidSize, renderFailed, mismatch, writeFailed }

func image(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw IconError.unreadable }
    guard image.width == 1024, image.height == 1024 else { throw IconError.invalidSize }
    return image
}

func opaque(_ image: CGImage) throws -> (image: CGImage, pixels: Data) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                  bytesPerRow: 4096, space: space,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw IconError.renderFailed }
    // The artwork is square and unmasked; watchOS applies the circular mask.
    context.setFillColor(CGColor(red: 0.91, green: 0.90, blue: 0.87, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    guard let output = context.makeImage(), let data = context.data else { throw IconError.renderFailed }
    return (output, Data(bytes: data, count: 4096 * 1024))
}

do {
    let expected = try opaque(image(at: source))
    if CommandLine.arguments.contains("--check") {
        let actualImage = try image(at: target)
        let actual = try opaque(actualImage)
        guard [.none, .noneSkipFirst, .noneSkipLast].contains(actualImage.alphaInfo),
              expected.pixels == actual.pixels else { throw IconError.mismatch }
        print("PASS: Watch icon matches iOS artwork, 1024x1024, opaque")
    } else {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw IconError.writeFailed }
        CGImageDestinationAddImage(output, expected.image, nil)
        guard CGImageDestinationFinalize(output) else { throw IconError.writeFailed }
        try (data as Data).write(to: target, options: .atomic)
        print("Updated Watch icon from the iOS artwork")
    }
} catch {
    fputs("Watch icon check/sync failed: \(error)\n", stderr)
    exit(1)
}
