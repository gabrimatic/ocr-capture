#!/usr/bin/env swift

import Cocoa
import Vision

// 1. Capture selection to temp file
let tempFile = "/tmp/ocr_capture_\(ProcessInfo.processInfo.processIdentifier).png"

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-i", "-t", "png", tempFile]

do {
    try task.run()
    task.waitUntilExit()
} catch {
    fputs("screencapture failed: \(error)\n", stderr)
    exit(1)
}

// User cancelled selection
guard task.terminationStatus == 0,
      FileManager.default.fileExists(atPath: tempFile) else {
    exit(0)
}

defer { try? FileManager.default.removeItem(atPath: tempFile) }

// 2. Load image
guard let image = NSImage(contentsOfFile: tempFile),
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    fputs("Failed to load captured image\n", stderr)
    exit(1)
}

// 3. OCR via Vision
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.automaticallyDetectsLanguage = true
request.revision = VNRecognizeTextRequestRevision3

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

do {
    try handler.perform([request])
} catch {
    fputs("OCR failed: \(error)\n", stderr)
    exit(1)
}

guard let observations = request.results, !observations.isEmpty else {
    fputs("No text found in selection\n", stderr)
    exit(0)
}

// 4. Extract text and copy to clipboard
let text = observations
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(text, forType: .string)

print("Copied \(text.count) characters to clipboard")
