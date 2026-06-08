import Foundation
import NaturalLanguage
import PDFKit

/// Cheap, LOCAL content signals used to make the static suggested-action list content-aware
/// (heuristics only — no network, no LLM). Produced by a BOUNDED, synchronous peek so it can run
/// inline where suggestions are computed (`FileInspector.suggestedActions`) without perceptible
/// latency: text/code read only the first ~16 KB, PDFs only the first page. Every read is
/// best-effort — on any failure the signals are empty (`.none`) and callers fall back to the plain
/// extension-based list.
///
/// Mirrors `FileFacts`' shape: an enum namespace with a nested `Sendable` struct + `nonisolated`
/// statics, so the work is safe to run off the main actor if we ever move it there.
enum FileSignals {

    struct Signals: Sendable {
        /// Dominant natural language of the peeked text, when confidently detected.
        var dominantLanguage: NLLanguage? = nil
        /// ≥ 3 date-like hits (NSDataDetector) — likely an agenda / contract / schedule.
        var hasManyDates = false
        /// Too little text to bother bulleting (drop "Summarise into Bullets").
        var isShort = false
        /// Enough text that summarising should lead.
        var isLong = false
        /// Contains a ``` fence — prose carrying code (offer "Explain This Code").
        var hasCodeFences = false
        /// Invoice/receipt-ish: money keywords or a currency-symbol+digit.
        var isMonetary = false

        /// Empty signals — every flag false, no language. The safe fallback.
        static let none = Signals()
    }

    // Bounds: enough text to detect language/structure, never enough to stall the drop.
    private static let maxPeekBytes   = 16_384   // text/code prefix
    private static let shortThreshold = 280      // chars → "too little to bullet"
    private static let longThreshold  = 4_000    // chars → "summarise leads"
    private static let manyDatesHits  = 3

    /// Peek a capped prefix of `url`'s content and derive signals. Text/code read the first
    /// ~16 KB via `FileHandle`; PDFs read only the first page string; anything else → `.none`.
    nonisolated static func peek(_ url: URL) -> Signals {
        guard let text = peekText(url) else { return .none }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        return analyse(trimmed)
    }

    // MARK: - Bounded content read

    private nonisolated static func peekText(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            // First page only — cheap relative to the whole document.
            guard let doc = PDFDocument(url: url), doc.pageCount > 0,
                  let page = doc.page(at: 0) else { return nil }
            return page.string
        }
        if FileInspector.isTextFile(url) || ["txt", "md", "rtf"].contains(ext) {
            return readPrefix(url)
        }
        return nil
    }

    /// First `maxPeekBytes` of the file as (lossy) UTF-8, via `FileHandle` so we never read a huge
    /// file whole. Returns nil on any error.
    private nonisolated static func readPrefix(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = (try? handle.read(upToCount: maxPeekBytes)) ?? nil,
              !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Analysis

    private nonisolated static func analyse(_ text: String) -> Signals {
        var s = Signals()
        let count = text.count
        s.isShort = count < shortThreshold
        s.isLong  = count >= longThreshold

        // Language — only trust a guess on enough text.
        if count >= 40 {
            let rec = NLLanguageRecognizer()
            rec.processString(text)
            if let lang = rec.dominantLanguage, lang != .undetermined {
                s.dominantLanguage = lang
            }
        }

        s.hasCodeFences = text.contains("```")
        s.isMonetary    = matchesMonetary(text)
        s.hasManyDates  = dateHitCount(text) >= manyDatesHits
        return s
    }

    private nonisolated static func matchesMonetary(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = ["invoice", "amount due", "subtotal", "balance due",
                        "total due", "vat", " tax "]
        if keywords.contains(where: lower.contains) { return true }
        // A currency symbol immediately followed by a digit (e.g. "$1,200", "€9").
        return text.range(of: #"[$€£¥]\s?\d"#, options: .regularExpression) != nil
    }

    /// Count date-ish hits with `NSDataDetector` (handles many formats) over the bounded peek.
    private nonisolated static func dateHitCount(_ text: String) -> Int {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.numberOfMatches(in: text, options: [], range: range)
    }
}
