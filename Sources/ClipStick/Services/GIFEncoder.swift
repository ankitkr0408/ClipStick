import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a recorded MP4 into a small looping GIF, stepping down quality until it fits the size budget.
enum GIFEncoder {
    struct Profile { let width: Int; let fps: Int }
    static let profiles = [Profile(width: 720, fps: 12), Profile(width: 560, fps: 10), Profile(width: 420, fps: 8), Profile(width: 320, fps: 6)]

    /// Returns the GIF written to `output`, or nil if the clip is too long / encoding failed.
    static func encode(video: URL, output: URL, maxBytes: Int = 3_000_000, maxSeconds: Double = 15) async -> URL? {
        let asset = AVURLAsset(url: video)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0, duration <= maxSeconds else { return nil }
        for profile in profiles {
            guard await write(asset: asset, duration: duration, profile: profile, to: output) else { continue }
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if size <= maxBytes || profile.width == profiles.last!.width { return output }
        }
        return nil
    }

    private static func write(asset: AVAsset, duration: Double, profile: Profile, to url: URL) async -> Bool {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: profile.width, height: profile.width * 4)   // width-limited; height follows aspect
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        let frameCount = max(1, Int(duration * Double(profile.fps)))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return false }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(profile.fps)]] as CFDictionary
        var added = 0
        for i in 0..<frameCount {
            let t = CMTime(seconds: Double(i) / Double(profile.fps), preferredTimescale: 600)
            guard let image = try? await gen.image(at: t).image else { continue }
            CGImageDestinationAddImage(dest, image, frameProps)
            added += 1
        }
        return added > 0 && CGImageDestinationFinalize(dest)
    }

    /// First frame of a video, used as the card thumbnail.
    static func poster(video: URL, maxPixel: Int = 720) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        return try? await gen.image(at: .zero).image
    }
}
