import SwiftUI
import Combine

/// Where file-PRODUCING utilities write their output. Mirrors `FavoriteToolsStore`'s
/// shape: a shared **General** directory plus one directory per `FileCategory`
/// (image / video / audio / text), each able to defer to General via `useGeneral`.
///
/// `resolved(for:)` returns the effective directory for a category, or `nil` when nothing
/// is configured — `nil` means "write next to the original" (the app's historical default).
/// Non-sandboxed app → plain paths, no security-scoped bookmarks.
struct CategoryOutput: Codable, Hashable {
    /// When true, this category uses the General directory (its own `path` is kept but
    /// ignored until the user turns this off).
    var useGeneral: Bool = true
    /// Absolute path to this category's output folder (nil = none chosen).
    var path: String?
}

@MainActor
final class OutputDirectoryStore: ObservableObject {
    static let shared = OutputDirectoryStore()

    private static let keyV1 = "outputDirectory.v1"

    /// Shared output folder used by any category whose `useGeneral` is on.
    @Published private(set) var generalPath: String?
    /// Per-category folders + their Use-General flags. Always has an entry for every case.
    @Published private(set) var categories: [FileCategory: CategoryOutput] = {
        var d: [FileCategory: CategoryOutput] = [:]
        for c in FileCategory.allCases { d[c] = CategoryOutput() }
        return d
    }()

    private init() { load() }

    // MARK: - Read

    /// The effective output directory for `category`: its own folder (when set and not
    /// deferring), else General, else `nil` (= write next to the original). Folders that
    /// no longer exist are skipped so a deleted directory falls back gracefully.
    func resolved(for category: FileCategory) -> URL? {
        if let cfg = categories[category], !cfg.useGeneral,
           let p = cfg.path, Self.isDirectory(p) {
            return URL(fileURLWithPath: p)
        }
        if let g = generalPath, Self.isDirectory(g) { return URL(fileURLWithPath: g) }
        return nil
    }

    /// Raw configured path for a scope (`nil` scope = General), ignoring Use-General.
    func path(for category: FileCategory?) -> String? {
        guard let c = category else { return generalPath }
        return categories[c]?.path
    }

    func useGeneral(for category: FileCategory) -> Bool {
        categories[category]?.useGeneral ?? true
    }

    /// Finder-style display name for a path (last component), or nil.
    static func displayName(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return FileManager.default.displayName(atPath: path)
    }

    // MARK: - Mutations

    func setGeneral(_ url: URL) {
        generalPath = url.standardizedFileURL.path
        persist()
    }

    func clearGeneral() {
        generalPath = nil
        persist()
    }

    /// Set a category's own folder and start using it (turns Use-General off).
    func setCategory(_ url: URL, for category: FileCategory) {
        var cfg = categories[category] ?? CategoryOutput()
        cfg.path = url.standardizedFileURL.path
        cfg.useGeneral = false
        categories[category] = cfg
        persist()
    }

    func clearCategory(for category: FileCategory) {
        var cfg = categories[category] ?? CategoryOutput()
        cfg.path = nil
        categories[category] = cfg
        persist()
    }

    func setUseGeneral(_ value: Bool, for category: FileCategory) {
        var cfg = categories[category] ?? CategoryOutput()
        cfg.useGeneral = value
        categories[category] = cfg
        persist()
    }

    // MARK: - Persistence

    private struct PersistedConfig: Codable {
        var generalPath: String?
        var categories: [String: CategoryOutput]
    }

    private func persist() {
        var dict: [String: CategoryOutput] = [:]
        for (c, cfg) in categories { dict[c.rawValue] = cfg }
        let config = PersistedConfig(generalPath: generalPath, categories: dict)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.keyV1)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.keyV1),
              let config = try? JSONDecoder().decode(PersistedConfig.self, from: data) else { return }
        generalPath = config.generalPath
        var cats: [FileCategory: CategoryOutput] = [:]
        for c in FileCategory.allCases {
            cats[c] = config.categories[c.rawValue] ?? CategoryOutput()
        }
        categories = cats
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
