import AppKit
import UniformTypeIdentifiers

/// Finder Quick Action: **Add to AI Drop**.
///
/// macOS launches this (sandboxed) extension with the Finder selection as input items.
/// We resolve them to file URLs, drop them onto a shared **named pasteboard**, and ping
/// the always-running main app via a **Darwin notification**. The non-sandboxed main app
/// reads the pasteboard and opens Stage 2 with the files. Fire and complete — no UI.
///
/// This is the ONLY source file the extension target needs. The hand-off uses a named
/// pasteboard + Darwin notification, so the extension requires no App Group or any other
/// special capability — just the mandatory app sandbox.
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let inputItems = (context.inputItems as? [NSExtensionItem]) ?? []
        let providers  = inputItems.flatMap { $0.attachments ?? [] }

        let fileType = UTType.fileURL.identifier   // "public.file-url"
        let group    = DispatchGroup()
        let lock     = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(fileType) {
            group.enter()
            provider.loadItem(forTypeIdentifier: fileType, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                switch item {
                case let u as URL:    url = u
                case let d as Data:   url = URL(dataRepresentation: d, relativeTo: nil)
                case let s as String: url = URL(string: s)
                default:              url = nil
                }
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            ShareHandoff.send(urls: urls)
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

/// Writes the selected file URLs onto the shared named pasteboard and pings the main app.
/// Kept self-contained so the extension target compiles with just this file.
enum ShareHandoff {
    static let darwinNotification = "com.wallbrecher.MacNotchAI.addFiles"
    static let pasteboardName = NSPasteboard.Name("com.wallbrecher.MacNotchAI.share")

    static func send(urls: [URL]) {
        guard !urls.isEmpty else { return }

        let pb = NSPasteboard(name: pasteboardName)
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])

        // Ping the always-running main app across the sandbox boundary.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotification as CFString),
            nil, nil, true
        )
    }
}
