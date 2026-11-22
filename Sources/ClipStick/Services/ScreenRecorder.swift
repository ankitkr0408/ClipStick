import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Writes ScreenCaptureKit frames to an H.264 MP4. All mutable state is guarded by a lock; frames arrive on a private queue.
final class FrameWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let lock = NSLock()
    private var started = false
    private var frames = 0

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(8_000_000, max(800_000, width * height * 3)),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        lock.lock(); defer { lock.unlock() }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sb.presentationTimeStamp)
            started = true
        }
        if writer.status == .writing, input.isReadyForMoreMediaData, input.append(sb) { frames += 1 }
    }

    /// Finalises the file. Returns false when no frame was ever captured.
    private func closeInput() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let ok = started && frames > 0 && writer.status == .writing
        if ok { input.markAsFinished() } else if started { writer.cancelWriting() }
        return ok
    }

    func finish() async -> Bool {
        guard closeInput() else { return false }
        await writer.finishWriting()
        return writer.status == .completed
    }
}

/// Region screen recording via ScreenCaptureKit (macOS 14+).
@MainActor
final class ScreenRecorder: NSObject, SCStreamDelegate {
    enum RecorderError: LocalizedError {
        case permissionDenied, noDisplay, empty
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "ClipStick needs Screen Recording permission. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
            case .noDisplay: "Couldn't find the display to record."
            case .empty: "Nothing was recorded."
            }
        }
    }

    private var stream: SCStream?
    private var frameWriter: FrameWriter?
    private(set) var outputURL: URL?
    private(set) var startedAt: Date?
    var isRecording: Bool { stream != nil }
    /// Called if the system stops the stream by itself (display unplugged, permission revoked…).
    var onUnexpectedStop: (() -> Void)?

    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    func start(screen: NSScreen, rect: CGRect) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { throw RecorderError.permissionDenied }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw RecorderError.permissionDenied }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw RecorderError.noDisplay }

        let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

        // Region in display points, top-left origin.
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let scale = screen.backingScaleFactor
        let cap: CGFloat = 1920
        let ratio = min(1, cap / max(rect.width * scale, rect.height * scale))
        let pw = max(2, Int(rect.width * scale * ratio) / 2 * 2), ph = max(2, Int(rect.height * scale * ratio) / 2 * 2)

        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = pw
        config.height = ph
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipstick-rec-\(UUID().uuidString).mp4")
        let writer = try FrameWriter(url: url, width: pw, height: ph)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: DispatchQueue(label: "clipstick.record", qos: .userInitiated))
        try await stream.startCapture()
        self.stream = stream
        frameWriter = writer
        outputURL = url
        startedAt = Date()
    }

    /// Stops capture and returns the finished MP4.
    func stop() async throws -> URL {
        guard let stream, let frameWriter, let url = outputURL else { throw RecorderError.empty }
        self.stream = nil
        try? await stream.stopCapture()
        let ok = await frameWriter.finish()
        self.frameWriter = nil
        outputURL = nil
        guard ok else { try? FileManager.default.removeItem(at: url); throw RecorderError.empty }
        return url
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onUnexpectedStop?() } }
    }

    /// Captures a static screenshot of the given display rectangle using ScreenCaptureKit with fallback to CGWindowListCreateImage.
    static func captureScreenshot(screen: NSScreen, rect: CGRect) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw RecorderError.permissionDenied
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw RecorderError.noDisplay
            }
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

            let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.sourceRect = local
            config.width = max(2, Int(rect.width * scale))
            config.height = max(2, Int(rect.height * scale))
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            // Fallback to CGWindowListCreateImage
            let localY = screen.frame.maxY - rect.maxY
            let captureRect = CGRect(x: rect.minX, y: localY, width: rect.width, height: rect.height)
            if let img = CGWindowListCreateImage(captureRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) {
                return img
            }
            throw error
        }
    }
}
