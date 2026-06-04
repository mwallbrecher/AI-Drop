import Foundation
import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import Speech
import AppKit

// MARK: - Errors

enum MediaToolError: LocalizedError {
    case noAudioTrack(URL)
    case noVideoTrack(URL)
    case unsupportedMedia(URL)
    case exportFailed(String)
    case frameFailed
    case gifFailed
    case speechUnavailable
    case speechDenied
    case speechFailed(String)
    case emptyTranscript(URL)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack(let u):   return "“\(u.lastPathComponent)” has no audio track to work with."
        case .noVideoTrack(let u):   return "“\(u.lastPathComponent)” has no video track to work with."
        case .unsupportedMedia(let u): return "“\(u.lastPathComponent)” is a media format this Mac can’t process."
        case .exportFailed(let m):   return "The media could not be exported: \(m)"
        case .frameFailed:           return "A still frame could not be created."
        case .gifFailed:             return "The GIF could not be created."
        case .speechUnavailable:     return "On-device speech recognition isn’t available right now."
        case .speechDenied:          return "Speech recognition permission was denied. Enable it in "
                                          + "System Settings ▸ Privacy & Security ▸ Speech Recognition."
        case .speechFailed(let m):   return "Transcription failed: \(m)"
        case .emptyTranscript(let u): return "No speech was detected in “\(u.lastPathComponent)”."
        }
    }
}

// MARK: - Engine
//
// Local, on-device media transforms on the session's video/audio files — AVFoundation +
// the Speech framework only, NO network, NO AI, ZERO operator API cost (transcription
// prefers on-device; even Apple's server fallback is Apple's free Speech service, not the
// proxy/Gemini bill). Every op writes a deduped SIBLING next to the source
// (`FileTools.uniqueDestination`) and is revealed in Finder by the caller.
//
// Concurrency: the type stays in the project's default-MainActor isolation, but no heavy
// work runs on the main actor — exports/transcription dispatch onto AVFoundation/Speech's
// own threads, and the CPU-bound GIF/frame loops run on a global queue via continuations.
// So `await`-ing these from the UI never beach-balls the overlay.

enum MediaTools {

    // MARK: Video → audio (extract)

    /// Pulls the audio track of a video into a sibling `.m4a`.
    static func extractAudio(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw MediaToolError.noAudioTrack(url) }
        let target = FileTools.uniqueDestination(url.deletingPathExtension().appendingPathExtension("m4a"))
        try await export(asset, to: target, as: .m4a, preset: AVAssetExportPresetAppleM4A)
        return target
    }

    // MARK: Audio → m4a (convert)

    /// Re-encodes an audio file (wav/aiff/caf/…) into a sibling AAC `.m4a`.
    static func convertAudio(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let target = FileTools.uniqueDestination(url.deletingPathExtension().appendingPathExtension("m4a"))
        try await export(asset, to: target, as: .m4a, preset: AVAssetExportPresetAppleM4A)
        return target
    }

    // MARK: Video container convert (mov ↔ mp4)

    /// Re-wraps a video into `fileType` (passthrough when the codecs allow it, otherwise a
    /// quality re-encode). Used for Convert-to-MP4 / Convert-to-MOV.
    static func convertVideo(_ url: URL, to fileType: AVFileType, ext: String) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let target = FileTools.uniqueDestination(url.deletingPathExtension().appendingPathExtension(ext))
        try await exportPreferringPassthrough(asset, to: target, as: fileType)
        return target
    }

    // MARK: Compress video (→ 720p mp4)

    /// Re-encodes a video down to 720p into a sibling `-compressed.mp4`.
    static func compressVideo(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        let target = FileTools.uniqueDestination(dir.appendingPathComponent("\(base)-compressed.mp4"))
        try await export(asset, to: target, as: .mp4, preset: AVAssetExportPreset1280x720)
        return target
    }

    // MARK: Remove audio (mute)

    /// Writes a sibling `-muted.mp4` containing only the video track(s).
    static func muteVideo(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let vtrack = videoTracks.first else { throw MediaToolError.noVideoTrack(url) }
        let duration  = try await asset.load(.duration)
        let transform = try await vtrack.load(.preferredTransform)

        let comp = AVMutableComposition()
        guard let compTrack = comp.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw MediaToolError.exportFailed("could not build a video-only composition") }
        try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vtrack, at: .zero)
        compTrack.preferredTransform = transform

        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        let target = FileTools.uniqueDestination(dir.appendingPathComponent("\(base)-muted.mp4"))
        try await exportPreferringPassthrough(comp, to: target, as: .mp4)
        return target
    }

    // MARK: Extract still frame

    /// Writes the midpoint frame of a video to a sibling `-frame.png`.
    static func extractFrame(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let mid = CMTime(seconds: max(0, CMTimeGetSeconds(duration) / 2), preferredTimescale: 600)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let cg = try await copyFrame(gen, at: mid)

        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        let target = FileTools.uniqueDestination(dir.appendingPathComponent("\(base)-frame.png"))
        try writePNG(cg, to: target)
        return target
    }

    // MARK: Video → animated GIF

    /// Samples the first `maxDuration` seconds of a video at `fps`, scaled to `maxWidth`,
    /// into a looping sibling `.gif`.
    static func videoToGIF(_ url: URL,
                           fps: Double = 10,
                           maxWidth: CGFloat = 480,
                           maxDuration: Double = 10) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let total = CMTimeGetSeconds(try await asset.load(.duration))
        guard total.isFinite, total > 0 else { throw MediaToolError.unsupportedMedia(url) }
        let clip = min(total, maxDuration)
        let frameCount = max(1, Int(clip * fps))

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxWidth, height: 0)   // 0 ⇒ derive height, keep aspect
        let tol = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = tol                 // loose ⇒ snap to nearby decoded frames (fast)
        gen.requestedTimeToleranceAfter  = tol

        let times = (0..<frameCount).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }
        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        let target = FileTools.uniqueDestination(dir.appendingPathComponent("\(base).gif"))
        try await encodeGIF(gen, times: times, fps: fps, to: target)
        return target
    }

    // MARK: Transcribe (Speech, on-device where supported)

    /// Transcribes the speech in an audio or video file into a sibling `.txt`. Video is
    /// reduced to a temporary `.m4a` first (more reliable than feeding a video container).
    static func transcribe(_ url: URL) async throws -> URL {
        let auth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard auth == .authorized else { throw MediaToolError.speechDenied }

        var sourceURL = url
        var tempURL: URL?
        if FileInspector.isVideoFile(url) {
            let asset = AVURLAsset(url: url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else { throw MediaToolError.noAudioTrack(url) }
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            try await export(asset, to: temp, as: .m4a, preset: AVAssetExportPresetAppleM4A)
            sourceURL = temp
            tempURL = temp
        }
        defer { if let t = tempURL { try? FileManager.default.removeItem(at: t) } }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw MediaToolError.speechUnavailable
        }
        let req = SFSpeechURLRecognitionRequest(url: sourceURL)
        req.shouldReportPartialResults = false
        // Prefer on-device: no network, no length cap, no operator cost.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

        let transcript = try await recognize(recognizer, req)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw MediaToolError.emptyTranscript(url) }

        let target = FileTools.uniqueDestination(url.deletingPathExtension().appendingPathExtension("txt"))
        do { try transcript.write(to: target, atomically: true, encoding: .utf8) }
        catch { throw MediaToolError.exportFailed(error.localizedDescription) }
        return target
    }

    // MARK: - Private helpers

    /// Runs an `AVAssetExportSession` and resolves only on completion. Cleans up a partial
    /// output on failure. AVFoundation drives the work on its own threads.
    private static func export(_ asset: AVAsset, to url: URL,
                               as fileType: AVFileType, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaToolError.unsupportedMedia(url)
        }
        session.outputURL = url
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw MediaToolError.exportFailed(session.error?.localizedDescription ?? "the export did not complete")
        }
    }

    /// Tries a fast passthrough re-wrap; on codec/container incompatibility re-encodes at
    /// highest quality (slower but reliable). Used for convert + mute.
    private static func exportPreferringPassthrough(_ asset: AVAsset, to url: URL,
                                                    as fileType: AVFileType) async throws {
        do {
            try await export(asset, to: url, as: fileType, preset: AVAssetExportPresetPassthrough)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try await export(asset, to: url, as: fileType, preset: AVAssetExportPresetHighestQuality)
        }
    }

    /// Decodes one frame off the main actor.
    private static func copyFrame(_ gen: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var actual = CMTime.zero
                    let cg = try gen.copyCGImage(at: time, actualTime: &actual)
                    cont.resume(returning: cg)
                } catch {
                    cont.resume(throwing: MediaToolError.frameFailed)
                }
            }
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw MediaToolError.frameFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw MediaToolError.frameFailed }
    }

    /// Samples the requested frames and writes a looping GIF — all on a global queue.
    private static func encodeGIF(_ gen: AVAssetImageGenerator, times: [CMTime],
                                  fps: Double, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.gif.identifier as CFString, times.count, nil
                ) else { cont.resume(throwing: MediaToolError.gifFailed); return }

                let fileProps: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFLoopCount as String: 0
                    ]
                ]
                CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

                let frameProps: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: 1.0 / fps,
                        kCGImagePropertyGIFUnclampedDelayTime as String: 1.0 / fps
                    ]
                ]

                var added = 0
                for t in times {
                    if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                        CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
                        added += 1
                    }
                }
                guard added > 0, CGImageDestinationFinalize(dest) else {
                    try? FileManager.default.removeItem(at: url)
                    cont.resume(throwing: MediaToolError.gifFailed); return
                }
                cont.resume(returning: ())
            }
        }
    }

    /// Bridges `SFSpeechRecognizer` to async — resolves once with the final transcript.
    private static func recognize(_ recognizer: SFSpeechRecognizer,
                                  _ request: SFSpeechURLRecognitionRequest) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                if done { return }
                if let error = error {
                    done = true
                    cont.resume(throwing: MediaToolError.speechFailed(error.localizedDescription))
                    return
                }
                guard let result = result, result.isFinal else { return }
                done = true
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
