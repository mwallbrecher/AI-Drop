import AppKit
import Quartz

/// Drives the system **Quick Look** panel (the Finder-spacebar preview) for the dropped
/// session files. Quick Look is NOT Finder-only — `QLPreviewPanel` is a shared system
/// panel any app can present. We're non-sandboxed and already hold the file URLs, so the
/// preview "just works" for images / PDF / video / audio / text / code, full-size.
///
/// Wiring: `QLPreviewPanel` walks the key window's responder chain to find a controller.
/// `OverlayWindow` implements the three `QLPreviewPanelController` hooks (accepts / begin /
/// end) and points the panel's `dataSource`/`delegate` at this singleton.
@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()
    private override init() { super.init() }

    /// Files to preview (existing-on-disk only) and the index to open on.
    private(set) var urls: [URL] = []
    private(set) var currentIndex: Int = 0

    /// Open Quick Look for `urls`, starting on `current`. The overlay must be made key
    /// first so the panel can reach `OverlayWindow` in the responder chain; the app is
    /// activated so the floating panel is interactive (it's an accessory/LSUIElement app).
    func present(urls: [URL], current: Int = 0) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        self.urls = existing
        self.currentIndex = min(max(0, current), existing.count - 1)

        if let overlay = NSApp.windows.first(where: { $0 is OverlayWindow }) {
            NSApp.activate(ignoringOtherApps: true)
            overlay.makeKeyAndOrderFront(nil)
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            // Already open (e.g. clicking a different pill): just re-point it.
            panel.reloadData()
            panel.currentPreviewItemIndex = currentIndex
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Data source

extension QuickLookController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        // NSURL conforms to QLPreviewItem natively.
        urls.indices.contains(index) ? (urls[index] as NSURL) : nil
    }
}

// MARK: - Delegate

extension QuickLookController: QLPreviewPanelDelegate {
    // The panel handles its own keys (◀ ▶ between files, Esc to close). Nothing custom
    // needed — the source-frame/zoom-animation hooks are optional and omitted.
}
