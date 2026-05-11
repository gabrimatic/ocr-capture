import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_text_image.swift TEXT OUTPUT.png\n", stderr)
    exit(2)
}

let text = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let imageSize = NSSize(width: 1200, height: 260)
let image = NSImage(size: imageSize)

image.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 72, weight: .regular),
    .foregroundColor: NSColor.black
]

(text as NSString).draw(
    at: NSPoint(x: 70, y: 86),
    withAttributes: attributes
)
image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render image\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
