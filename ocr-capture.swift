import Cocoa
import Foundation
import ImageIO
import Vision

// MARK: - CLI

struct Configuration {
    var imagePath: String?
    var printToStdout = false
    var copyToClipboard = true
    var quiet = false
    var timeoutSeconds = 15
    var showHelp = false
}

enum OCRCaptureError: Error {
    case usage(String)
    case imageFileNotFound(String)
    case captureFailed(String)
    case imageLoadFailed(String)
    case emptyImage
    case ocrTimedOut(Int)
    case ocrFailed(String)

    var message: String {
        switch self {
        case .usage(let message):
            return message
        case .imageFileNotFound(let path):
            return "Image file not found: \(path)"
        case .captureFailed(let message):
            return "Screen capture failed: \(message)"
        case .imageLoadFailed(let path):
            return "Failed to load image: \(path)"
        case .emptyImage:
            return "Empty capture. Check Screen Recording permission in System Settings."
        case .ocrTimedOut(let seconds):
            return "OCR timed out after \(seconds) seconds."
        case .ocrFailed(let message):
            return "OCR failed: \(message)"
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage:
            return 2
        default:
            return 1
        }
    }
}

let usage = """
Usage: ocr-capture [options]

Select a screen region, run OCR, and copy the recognized text to the clipboard.
With --file, OCR an existing image instead of starting an interactive capture.

Options:
  -f, --file PATH       OCR an existing image file.
      --stdout          Print recognized text to stdout.
      --no-copy         Do not copy recognized text to the clipboard.
      --quiet           Suppress sounds and notifications.
      --timeout SECONDS OCR timeout in seconds. Default: 15.
  -h, --help            Show this help.
"""

func parseArguments(_ rawArguments: [String]) throws -> Configuration {
    var configuration = Configuration()
    let arguments = Array(rawArguments.dropFirst())
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "-h", "--help":
            configuration.showHelp = true
        case "-f", "--file":
            index += 1
            guard index < arguments.count,
                  !arguments[index].hasPrefix("-") else {
                throw OCRCaptureError.usage("Missing value for \(argument).")
            }
            configuration.imagePath = arguments[index]
        case "--stdout":
            configuration.printToStdout = true
        case "--no-copy":
            configuration.copyToClipboard = false
        case "--quiet", "--no-notify":
            configuration.quiet = true
        case "--timeout":
            index += 1
            guard index < arguments.count else {
                throw OCRCaptureError.usage("Missing value for --timeout.")
            }
            guard let seconds = Int(arguments[index]), seconds > 0 else {
                throw OCRCaptureError.usage("Timeout must be a positive integer.")
            }
            configuration.timeoutSeconds = seconds
        default:
            if argument.hasPrefix("-") {
                throw OCRCaptureError.usage("Unknown option: \(argument).")
            }

            if configuration.imagePath == nil {
                configuration.imagePath = argument
            } else {
                throw OCRCaptureError.usage("Unexpected argument: \(argument).")
            }
        }

        index += 1
    }

    return configuration
}

// MARK: - Feedback

func notify(_ title: String, _ body: String, quiet: Bool) {
    guard !quiet else { return }

    func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    let script = "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    try? task.run()
    task.waitUntilExit()
}

func playSound(_ name: String, quiet: Bool) {
    guard !quiet else { return }

    if let sound = NSSound(named: NSSound.Name(name)) {
        sound.play()
    }
}

func reportError(_ error: OCRCaptureError, quiet: Bool) {
    fputs(error.message + "\n", stderr)

    switch error {
    case .usage:
        break
    default:
        playSound("Basso", quiet: quiet)
        notify("OCR Capture", error.message, quiet: quiet)
    }
}

// MARK: - Capture

func screencaptureExecutablePath() -> String {
    for path in ["/usr/sbin/screencapture", "/usr/bin/screencapture"] {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return "screencapture"
}

func makeTemporaryPNGPath() -> String {
    let template = NSTemporaryDirectory() + "ocr_capture_XXXXXX.png"
    var buffer = Array(template.utf8CString)
    let descriptor = mkstemps(&buffer, 4)

    guard descriptor != -1 else {
        return NSTemporaryDirectory() + "ocr_capture_\(ProcessInfo.processInfo.processIdentifier).png"
    }

    close(descriptor)
    let path = String(cString: buffer)
    unlink(path)
    return path
}

func captureInteractiveRegion() throws -> URL? {
    let tempFile = makeTemporaryPNGPath()
    let task = Process()
    task.executableURL = URL(fileURLWithPath: screencaptureExecutablePath())
    task.arguments = ["-i", "-t", "png", tempFile]

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        throw OCRCaptureError.captureFailed(error.localizedDescription)
    }

    guard task.terminationStatus == 0,
          FileManager.default.fileExists(atPath: tempFile) else {
        return nil
    }

    return URL(fileURLWithPath: tempFile)
}

func imageURL(from path: String) throws -> URL {
    let expandedPath = (path as NSString).expandingTildeInPath
    var isDirectory = ObjCBool(false)

    guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        throw OCRCaptureError.imageFileNotFound(path)
    }

    return URL(fileURLWithPath: expandedPath)
}

// MARK: - Image loading

func loadImage(at url: URL) throws -> CGImage {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw OCRCaptureError.imageLoadFailed(url.path)
    }

    guard cgImage.width > 0, cgImage.height > 0 else {
        throw OCRCaptureError.emptyImage
    }

    return cgImage
}

// MARK: - OCR

func recognizedText(from observations: [VNRecognizedTextObservation]) -> String {
    let sorted = observations.sorted { a, b in
        guard let textA = a.topCandidates(1).first,
              let textB = b.topCandidates(1).first else {
            return false
        }

        let rectA = (try? textA.boundingBox(for: textA.string.startIndex..<textA.string.endIndex))?.boundingBox ?? a.boundingBox
        let rectB = (try? textB.boundingBox(for: textB.string.startIndex..<textB.string.endIndex))?.boundingBox ?? b.boundingBox

        let rowTolerance = max(rectA.height, rectB.height) * 0.45
        if abs(rectA.midY - rectB.midY) > rowTolerance {
            return rectA.midY > rectB.midY
        }

        return rectA.minX < rectB.minX
    }

    return sorted
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}

func recognizeText(in image: CGImage, timeoutSeconds: Int) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    request.revision = VNRecognizeTextRequestRevision3

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let ocrQueue = DispatchQueue(label: "ocr")
    let semaphore = DispatchSemaphore(value: 0)
    var ocrError: Error?

    ocrQueue.async {
        do {
            try handler.perform([request])
        } catch {
            ocrError = error
        }
        semaphore.signal()
    }

    let result = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
    if result == .timedOut {
        throw OCRCaptureError.ocrTimedOut(timeoutSeconds)
    }

    if let error = ocrError {
        throw OCRCaptureError.ocrFailed(error.localizedDescription)
    }

    return recognizedText(from: request.results ?? [])
}

// MARK: - Clipboard

func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

// MARK: - Main

let configuration: Configuration

do {
    configuration = try parseArguments(CommandLine.arguments)
} catch let error as OCRCaptureError {
    reportError(error, quiet: true)
    fputs("\n\(usage)", stderr)
    exit(error.exitCode)
}

if configuration.showHelp {
    print(usage)
    exit(0)
}

do {
    let capturedURL: URL?
    let sourceURL: URL

    if let imagePath = configuration.imagePath {
        capturedURL = nil
        sourceURL = try imageURL(from: imagePath)
    } else {
        guard let captureURL = try captureInteractiveRegion() else {
            exit(0)
        }
        capturedURL = captureURL
        sourceURL = captureURL
    }

    defer {
        if let capturedURL {
            try? FileManager.default.removeItem(at: capturedURL)
        }
    }

    let image = try loadImage(at: sourceURL)
    let text = try recognizeText(in: image, timeoutSeconds: configuration.timeoutSeconds)

    guard !text.isEmpty else {
        let message = configuration.imagePath == nil ? "No text found in selection." : "No text found in image."
        playSound("Pop", quiet: configuration.quiet)
        notify("OCR Capture", message, quiet: configuration.quiet)
        exit(0)
    }

    if configuration.copyToClipboard {
        copyToClipboard(text)
    }

    if configuration.printToStdout {
        print(text)
    }

    let lineCount = text.components(separatedBy: "\n").count
    playSound("Pop", quiet: configuration.quiet)
    let action = configuration.copyToClipboard ? "Copied" : "Recognized"
    let suffix = configuration.copyToClipboard ? " to clipboard" : ""
    notify("OCR Capture", "\(action) \(lineCount) line\(lineCount == 1 ? "" : "s")\(suffix).", quiet: configuration.quiet)

    RunLoop.current.run(until: Date(timeIntervalSinceNow: configuration.quiet ? 0 : 0.3))
} catch let error as OCRCaptureError {
    reportError(error, quiet: configuration.quiet)
    exit(error.exitCode)
}
