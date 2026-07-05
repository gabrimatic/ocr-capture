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
    case clipboardFailed

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
        case .clipboardFailed:
            return "Failed to copy text to the clipboard."
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

let maxTimeoutSeconds = 3600

let usage = """
Usage: ocr-capture [options]

Select a screen region, run OCR, and copy the recognized text to the clipboard.
With --file, OCR an existing image instead of starting an interactive capture.

Options:
  -f, --file PATH       OCR an existing image file.
      --stdout          Print recognized text to stdout.
      --no-copy         Do not copy recognized text to the clipboard.
      --quiet           Suppress sounds and notifications (alias: --no-notify).
      --timeout SECONDS OCR timeout in seconds (1-\(maxTimeoutSeconds)). Default: 15.
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
            guard configuration.imagePath == nil else {
                throw OCRCaptureError.usage("Multiple image paths specified.")
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
            guard let seconds = Int(arguments[index]), seconds > 0, seconds <= maxTimeoutSeconds else {
                throw OCRCaptureError.usage("Timeout must be between 1 and \(maxTimeoutSeconds) seconds.")
            }
            configuration.timeoutSeconds = seconds
        default:
            if argument.hasPrefix("-") {
                throw OCRCaptureError.usage("Unknown option: \(argument).")
            }

            if configuration.imagePath == nil {
                configuration.imagePath = argument
            } else {
                throw OCRCaptureError.usage("Multiple image paths specified.")
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
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }

    let script = "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        // Notifications are best-effort; a missing osascript must not crash the tool.
    }
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
        return NSTemporaryDirectory() + "ocr_capture_\(UUID().uuidString).png"
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

// MARK: - Stdout hygiene

// Vision's model loader prints diagnostics directly to stdout, which would
// corrupt --stdout output for scripts. Point fd 1 at /dev/null for the rest of
// the process and hand back the original stdout for writing recognized text.
func protectStdout() -> FileHandle {
    let saved = dup(STDOUT_FILENO)
    guard saved != -1 else {
        return .standardOutput
    }

    let devNull = open("/dev/null", O_WRONLY)
    if devNull != -1 {
        dup2(devNull, STDOUT_FILENO)
        close(devNull)
    }

    return FileHandle(fileDescriptor: saved, closeOnDealloc: false)
}

// MARK: - OCR

func recognizedText(from observations: [VNRecognizedTextObservation]) -> String {
    struct Line {
        let text: String
        let box: CGRect
    }

    let lines: [Line] = observations.compactMap { observation in
        guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else {
            return nil
        }

        let range = candidate.string.startIndex..<candidate.string.endIndex
        let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
        return Line(text: candidate.string, box: box)
    }

    // Vision coordinates are normalized with the origin at the bottom-left, so a
    // larger midY is closer to the top of the image. Sort by a deterministic
    // total order first, then cluster into visual rows; a tolerance-based
    // comparator fed straight to sorted(by:) would not be a strict weak ordering.
    let byVertical = lines.sorted { a, b in
        if a.box.midY != b.box.midY { return a.box.midY > b.box.midY }
        if a.box.minX != b.box.minX { return a.box.minX < b.box.minX }
        return a.text < b.text
    }

    var rows: [[Line]] = []
    var currentRowMidY = CGFloat(0)

    for line in byVertical {
        if let previous = rows.last?.last {
            let tolerance = max(line.box.height, previous.box.height) * 0.45
            if abs(line.box.midY - currentRowMidY) <= tolerance {
                rows[rows.count - 1].append(line)
                let row = rows[rows.count - 1]
                currentRowMidY = row.reduce(CGFloat(0)) { $0 + $1.box.midY } / CGFloat(row.count)
                continue
            }
        }

        rows.append([line])
        currentRowMidY = line.box.midY
    }

    return rows
        .flatMap { row in
            row.sorted { a, b in
                if a.box.minX != b.box.minX { return a.box.minX < b.box.minX }
                return a.text < b.text
            }
        }
        .map(\.text)
        .joined(separator: "\n")
}

final class ErrorBox {
    var error: Error?
}

struct PendingRecognition {
    let request: VNRecognizeTextRequest
    let semaphore: DispatchSemaphore
    let errorBox: ErrorBox
}

// Test hook: the CLI test suite sets these to force the timeout/fallback paths
// deterministically. Both are inert in normal use.
func stallForTestingIfRequested(level: VNRequestTextRecognitionLevel) {
    let environment = ProcessInfo.processInfo.environment
    var keys = ["OCR_CAPTURE_TEST_STALL_MS"]
    if level == .accurate {
        keys.append("OCR_CAPTURE_TEST_STALL_ACCURATE_MS")
    }

    for key in keys {
        if let value = environment[key], let milliseconds = UInt32(value), milliseconds > 0 {
            Thread.sleep(forTimeInterval: TimeInterval(milliseconds) / 1000)
        }
    }
}

func startRecognition(image: CGImage, level: VNRequestTextRecognitionLevel) -> PendingRecognition {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = true
    if level == .accurate {
        request.automaticallyDetectsLanguage = true
    }

    let errorBox = ErrorBox()
    let semaphore = DispatchSemaphore(value: 0)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])

    DispatchQueue.global(qos: .userInitiated).async {
        stallForTestingIfRequested(level: level)
        do {
            try handler.perform([request])
        } catch {
            errorBox.error = error
        }
        semaphore.signal()
    }

    return PendingRecognition(request: request, semaphore: semaphore, errorBox: errorBox)
}

struct RecognitionResult {
    let text: String
    let usedFastFallback: Bool
    // Still-running accurate attempt after a fallback; waiting on it lets macOS
    // finish compiling the accurate model so the next run succeeds first try.
    let pendingWarmup: PendingRecognition?
}

func recognizeText(in image: CGImage, timeoutSeconds: Int) throws -> RecognitionResult {
    let accurate = startRecognition(image: image, level: .accurate)

    if accurate.semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .success {
        if let error = accurate.errorBox.error {
            throw OCRCaptureError.ocrFailed(error.localizedDescription)
        }

        let text = recognizedText(from: accurate.request.results ?? [])
        return RecognitionResult(text: text, usedFastFallback: false, pendingWarmup: nil)
    }

    // Accurate recognition can stall far beyond any sane timeout while macOS
    // compiles the model on first use after an OS update. Fast recognition uses
    // an independent, quick-loading model, so degrade gracefully instead of
    // failing outright.
    let fast = startRecognition(image: image, level: .fast)
    let fastTimeout = min(timeoutSeconds, 10)

    guard fast.semaphore.wait(timeout: .now() + .seconds(fastTimeout)) == .success else {
        throw OCRCaptureError.ocrTimedOut(timeoutSeconds)
    }

    if let error = fast.errorBox.error {
        throw OCRCaptureError.ocrFailed(error.localizedDescription)
    }

    let text = recognizedText(from: fast.request.results ?? [])
    return RecognitionResult(text: text, usedFastFallback: true, pendingWarmup: accurate)
}

// MARK: - Clipboard

func copyToClipboard(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
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

// exit() skips pending defer blocks, so the body runs in a function whose
// early exits are returns (cleanup always runs) and the process exits once,
// at the very end.
var pendingWarmup: PendingRecognition?

func run() -> Int32 {
    do {
        let capturedURL: URL?
        let sourceURL: URL

        if let imagePath = configuration.imagePath {
            capturedURL = nil
            sourceURL = try imageURL(from: imagePath)
        } else {
            guard let captureURL = try captureInteractiveRegion() else {
                return 0
            }
            capturedURL = captureURL
            sourceURL = captureURL
        }

        defer {
            if let capturedURL {
                try? FileManager.default.removeItem(at: capturedURL)
            }
        }

        let cleanStdout = protectStdout()
        let image = try loadImage(at: sourceURL)
        let result = try recognizeText(in: image, timeoutSeconds: configuration.timeoutSeconds)
        let text = result.text

        if result.usedFastFallback {
            fputs("Accurate OCR timed out; used fast recognition instead.\n", stderr)
            pendingWarmup = result.pendingWarmup
        }

        guard !text.isEmpty else {
            let message = configuration.imagePath == nil ? "No text found in selection." : "No text found in image."
            playSound("Pop", quiet: configuration.quiet)
            notify("OCR Capture", message, quiet: configuration.quiet)
            return 0
        }

        if configuration.copyToClipboard {
            guard copyToClipboard(text) else {
                throw OCRCaptureError.clipboardFailed
            }
        }

        if configuration.printToStdout {
            cleanStdout.write(Data((text + "\n").utf8))
        }

        let lineCount = text.components(separatedBy: "\n").count
        playSound("Pop", quiet: configuration.quiet)
        let action = configuration.copyToClipboard ? "Copied" : "Recognized"
        let suffix = configuration.copyToClipboard ? " to clipboard" : ""
        notify("OCR Capture", "\(action) \(lineCount) line\(lineCount == 1 ? "" : "s")\(suffix).", quiet: configuration.quiet)
        return 0
    } catch let error as OCRCaptureError {
        reportError(error, quiet: configuration.quiet)
        return error.exitCode
    } catch {
        reportError(.ocrFailed(error.localizedDescription), quiet: configuration.quiet)
        return 1
    }
}

let exitCode = run()

// NSSound.play() is asynchronous: every path that played a feedback sound needs
// a moment of run-loop time before the process exits, or the sound is cut off.
if !configuration.quiet {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
}

// Interactive captures are launched from a hotkey, so nothing waits on this
// process: give an abandoned accurate attempt time to finish compiling its
// model (macOS caches the result) so the next capture succeeds without
// fallback. File mode exits immediately to keep scripted pipelines fast.
if let warmup = pendingWarmup, configuration.imagePath == nil {
    _ = warmup.semaphore.wait(timeout: .now() + .seconds(90))
}

exit(exitCode)
