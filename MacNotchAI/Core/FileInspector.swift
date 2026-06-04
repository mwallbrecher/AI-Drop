import Foundation

struct FileInspector {
    static func suggestedActions(for url: URL) -> [AIAction] {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return [.summariseBullets, .extractKeyDates, .extractKeyPoints, .translateGerman, .rephraseFormal]
        case "txt", "md", "rtf":
            return [.summariseBullets, .summariseShort, .rephraseFormal, .rephraseCasual, .translateGerman]
        case "docx", "doc", "pages":
            return [.summariseBullets, .extractKeyPoints, .rephraseFormal, .translateGerman]
        case "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "rb", "java", "kt", "cpp", "c", "cs":
            return [.explainCode, .findBugs, .addDocstring, .refactor]
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "tiff":
            return [.describeImage, .extractTextFromImage, .generateAltText]
        case "csv":
            return [.summariseBullets, .extractKeyPoints]
        case "json", "xml", "yaml", "yml":
            return [.explainCode, .summariseBullets]
        case _ where isMediaFile(url):
            // Video / audio: no hosted-AI actions (text & vision models can't read raw
            // media), BUT still DROPPABLE — the user can open them in a favorite app
            // (Pillar 1) or run a local file utility (Pillar 2). See isUnsupportedFileType.
            return []
        case "zip", "rar", "7z", "tar", "gz",
             "dmg", "pkg", "exe":
            return []   // truly unsupported — caller routes to the error stage
        default:
            return [.summariseBullets, .summariseShort, .extractKeyPoints]
        }
    }

    /// Returns the union of suggested actions for all given URLs, preserving the
    /// order from the first URL and appending actions from subsequent URLs that
    /// aren't already present.
    static func suggestedActions(forAll urls: [URL]) -> [AIAction] {
        guard !urls.isEmpty else { return [] }
        var seen = Set<AIAction>()
        var result: [AIAction] = []
        for url in urls {
            for action in suggestedActions(for: url) {
                if seen.insert(action).inserted {
                    result.append(action)
                }
            }
        }
        return result
    }

    /// Returns true for file types AI Drop cannot process at all (archives, installers).
    /// Drop handlers use this to route directly to the error stage.
    ///
    /// NOTE: video/audio are NOT unsupported — they have no AI actions but ARE droppable
    /// (Open-in + file utilities), so they are exempted here and land in the chips stage.
    static func isUnsupportedFileType(_ url: URL) -> Bool {
        if isMediaFile(url) { return false }
        return suggestedActions(for: url).isEmpty
    }

    static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    static let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm"]
    static let audioExtensions = ["mp3", "aac", "wav", "flac", "ogg", "m4a", "aiff", "aif"]

    static func isVideoFile(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Plain-text / code / data extensions whose CONTENTS are line-oriented UTF-8 text.
    /// Deliberately NOT pdf/docx/rtf (those are containers, not plain text) — the text
    /// line tools (sort/dedupe/count/base64) only make sense on real text. `b64`/`base64`
    /// are included so a dropped Base64 file offers Decode.
    static let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "json", "ndjson", "jsonl",
        "xml", "yaml", "yml", "toml", "ini", "conf", "cfg", "properties", "env",
        "log", "html", "htm", "css", "scss", "sass", "less",
        "js", "mjs", "cjs", "jsx", "ts", "tsx", "swift", "py", "rb", "go", "rs",
        "java", "kt", "kts", "gradle", "c", "h", "cpp", "cc", "hpp", "hh", "cs",
        "m", "mm", "php", "sh", "bash", "zsh", "fish", "sql", "r", "lua", "pl",
        "pm", "dart", "scala", "clj", "ex", "exs", "vue", "svelte", "tex",
        "srt", "vtt", "gitignore", "b64", "base64"
    ]

    /// True for line-oriented UTF-8 text/code/data files (gates the text-tool cluster).
    static func isTextFile(_ url: URL) -> Bool {
        textExtensions.contains(url.pathExtension.lowercased())
    }

    /// Video or audio. These carry no hosted-AI path (the chips stage hides the prompt
    /// field + AI tabs for them) but are droppable for Open-in / file utilities.
    static func isMediaFile(_ url: URL) -> Bool {
        isVideoFile(url) || isAudioFile(url)
    }

    static func requiresVision(_ url: URL) -> Bool {
        return isImageFile(url)
    }

    /// The favorite-apps category a dropped file belongs to. `.text` is the catch-all
    /// for everything droppable that isn't image/video/audio (PDF, code, json, docx, …).
    static func category(for url: URL) -> FileCategory {
        if isImageFile(url) { return .image }
        if isVideoFile(url) { return .video }
        if isAudioFile(url) { return .audio }
        return .text
    }
}

/// Coarse file class used to scope the user's favorite apps (Settings → Favorite Tools).
/// Order here drives the order of the Settings tabs.
enum FileCategory: String, CaseIterable, Codable {
    case image, video, audio, text

    /// Tab label shown in Settings.
    var title: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .text:  return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .text:  return "doc.text"
        }
    }
}
