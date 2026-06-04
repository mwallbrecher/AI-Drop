import SwiftUI
import AppKit

/// The numbered "Open in" launch row shown in the chips stage (Pillar 1).
///
/// Each favorite app is a tappable icon carrying its `Option+N` number badge.
/// Clicking — or pressing `Option+N` while a file is staged (see AppDelegate's
/// tool-hotkey monitor) — opens ALL staged files in that app and dismisses the
/// overlay. With no favorites it collapses to a single muted hint (no dead UI).
///
/// Heights are fixed via `ChipsLayout.toolRowHeight` / `.toolHintHeight` so this
/// view and `AppDelegate.sizeForStage` agree exactly on the window height.
struct ToolRow: View {
    @ObservedObject private var store = FavoriteToolsStore.shared
    @ObservedObject private var vm = OverlayViewModel.shared
    @Environment(\.uiScale) private var scale

    /// The favorites that apply to the file(s) currently staged — the dropped file's
    /// category list, or General when that category defers to it.
    private var tools: [FavoriteTool] {
        store.resolvedTools(for: vm.sessionFileURLs)
    }

    var body: some View {
        Group {
            if tools.isEmpty {
                emptyHint
            } else {
                populated
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: (tools.isEmpty ? ChipsLayout.toolHintHeight : ChipsLayout.toolRowHeight) * scale,
            alignment: .leading
        )
    }

    private var emptyHint: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 10 * scale, weight: .semibold))
            Text("Add favorite apps in Settings to open files in one click.")
                .font(.system(size: 11 * scale))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(.white.opacity(0.30))
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            // Two-tone caption: "OPEN IN" (lighter grey) + a dimmer "⌥+" hotkey hint.
            // The per-app number badges on the icons spell out which N to press.
            HStack(spacing: 4 * scale) {
                Text("OPEN IN")
                    .foregroundColor(.white.opacity(0.40))
                Text("⌥+")
                    .foregroundColor(.white.opacity(0.28))
            }
            .font(.system(size: 9 * scale, weight: .semibold))
            .tracking(0.6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8 * scale) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { idx, tool in
                        ToolButton(tool: tool, number: idx + 1) {
                            store.launch(tool, with: vm.sessionFileURLs)
                        }
                    }
                    // Trailing "+" — opens Settings ▸ Favorite Tools to add another app.
                    AddToolButton {
                        NotificationCenter.default.post(name: .showFavoriteTools, object: nil)
                    }
                }
            }
        }
    }
}

/// The dashed "+" cell that sits after the favorite-app icons. Same 40×40 glass
/// footprint as `ToolButton` so the row reads as one family; the dashed border +
/// plus glyph signal "add" without a number badge. Opens the Favorite Tools settings.
private struct AddToolButton: View {
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 30 * scale, height: 30 * scale)
                .padding(5 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(0.20),
                                    style: StrokeStyle(lineWidth: 1, dash: [3 * scale, 2.5 * scale])
                                )
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a favorite app")
    }
}

/// One favorite-app cell: the app icon in a glass square with a small `Option+N`
/// badge. The app name lives in the tooltip to keep the row compact.
private struct ToolButton: View {
    let tool: FavoriteTool
    let number: Int
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: FavoriteToolsStore.shared.icon(for: tool))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30 * scale, height: 30 * scale)
                    .padding(5 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )

                // Badge sits INSIDE the cell's top-right corner so the ScrollView
                // never clips it (a positive outward offset gets cut off).
                Text("\(number)")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 14 * scale, height: 14 * scale)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                    .offset(x: -2 * scale, y: 2 * scale)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in \(tool.name)  (⌥\(number))")
    }
}
