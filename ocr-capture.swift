import Cocoa
import Vision
import UserNotifications

// MARK: - Notification

func notify(_ title: String, _ body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}

func playSound(_ name: String) {
    if let sound = NSSound(named: NSSound.Name(name)) {
        sound.play()
    }
}

// MARK: - Capture

let screencapturePath: String = {
    for path in ["/usr/sbin/screencapture", "/usr/bin/screencapture"] {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    return "screencapture"
}()

let tempFile: String = {
    let template = NSTemporaryDirectory() + "ocr_capture_XXXXXX"
    var buf = Array(template.utf8CString)
    guard mkstemp(&buf) != -1 else {
        return NSTemporaryDirectory() + "ocr_capture_\(ProcessInfo.processInfo.processIdentifier).png"
    }
    let path = String(cString: buf)
    unlink(path) // remove the empty file; screencapture will create it
    return path + ".png"
}()

let task = Process()
task.executableURL = URL(fileURLWithPath: screencapturePath)
task.arguments = ["-i", "-t", "png", tempFile]

do {
    try task.run()
    task.waitUntilExit()
} catch {
    playSound("Basso")
    notify("OCR Capture", "Screen capture failed: \(error.localizedDescription)")
    exit(1)
}

// User cancelled selection
guard task.terminationStatus == 0,
      FileManager.default.fileExists(atPath: tempFile) else {
    exit(0)
}

defer { try? FileManager.default.removeItem(atPath: tempFile) }

// MARK: - Load image

guard let imageSource = CGImageSourceCreateWithURL(
    URL(fileURLWithPath: tempFile) as CFURL, nil
), let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    playSound("Basso")
    notify("OCR Capture", "Failed to load captured image.")
    exit(1)
}

// Check for empty/black image (Screen Recording permission issue)
let width = cgImage.width
let height = cgImage.height
if width == 0 || height == 0 {
    playSound("Basso")
    notify("OCR Capture", "Empty capture. Check Screen Recording permission in System Settings.")
    exit(1)
}

// MARK: - OCR

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.automaticallyDetectsLanguage = true
request.revision = VNRecognizeTextRequestRevision3

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

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

let timeoutSeconds = 15
let result = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))

if result == .timedOut {
    playSound("Basso")
    notify("OCR Capture", "OCR timed out after \(timeoutSeconds) seconds.")
    exit(1)
}

if let error = ocrError {
    playSound("Basso")
    notify("OCR Capture", "OCR failed: \(error.localizedDescription)")
    exit(1)
}

guard let observations = request.results, !observations.isEmpty else {
    playSound("Pop")
    notify("OCR Capture", "No text found in selection.")
    exit(0)
}

// MARK: - Sort by reading order (top-to-bottom, left-to-right)

let sorted = observations.sorted { a, b in
    guard let boxA = a.topCandidates(1).first,
          let boxB = b.topCandidates(1).first else { return false }
    let rectA = try? boxA.boundingBox(for: boxA.string.startIndex..<boxA.string.endIndex)
    let rectB = try? boxB.boundingBox(for: boxB.string.startIndex..<boxB.string.endIndex)
    // Vision coordinates: origin at bottom-left, y increases upward
    let yA = rectA?.boundingBox.origin.y ?? a.boundingBox.origin.y
    let yB = rectB?.boundingBox.origin.y ?? b.boundingBox.origin.y
    // Sort top-to-bottom: higher y = higher on screen in Vision coords
    if abs(yA - yB) > 0.01 { return yA > yB }
    let xA = rectA?.boundingBox.origin.x ?? a.boundingBox.origin.x
    let xB = rectB?.boundingBox.origin.x ?? b.boundingBox.origin.x
    return xA < xB
}

// MARK: - Clipboard

let text = sorted
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(text, forType: .string)

let lineCount = text.components(separatedBy: "\n").count
playSound("Pop")
notify("OCR Capture", "Copied \(lineCount) line\(lineCount == 1 ? "" : "s") to clipboard.")

// Give notification time to fire
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
