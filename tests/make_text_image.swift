import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_text_image.swift TEXT OUTPUT.png (TEXT may contain \\n for multiple lines)\n", stderr)
    exit(2)
}

let lines = CommandLine.arguments[1].components(separatedBy: "\\n")
let outputPath = CommandLine.arguments[2]

let fontSize = CGFloat(72)
let lineSpacing = CGFloat(40)
let margin = CGFloat(70)
let lineHeight = fontSize + lineSpacing
let imageSize = NSSize(width: 1200, height: margin * 2 + lineHeight * CGFloat(lines.count))
let image = NSImage(size: imageSize)

image.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
    .foregroundColor: NSColor.black
]

for (index, line) in lines.enumerated() {
    // AppKit's origin is bottom-left; draw the first line at the top.
    let y = imageSize.height - margin - lineHeight * CGFloat(index + 1) + lineSpacing / 2
    (line as NSString).draw(
        at: NSPoint(x: margin, y: y),
        withAttributes: attributes
    )
}
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
