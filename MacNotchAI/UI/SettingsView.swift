import SwiftUI
import UniformTypeIdentifiers

/// Which slice of the settings to show. The menu-bar dropdown opens the window
/// scoped to a single setting (`.windowSize` / `.customPrompt` / `.favoriteTools` /
/// `.aiProvider`); the system ⌘, Settings scene still shows everything (`.all`).
enum SettingsSection: String {
    case all, windowSize, customPrompt, favoriteTools, aiProvider

    /// Title for the settings window when opened scoped to this section.
    var windowTitle: String {
        switch self {
        case .all:           return "AI Drop Settings"
        case .windowSize:    return "Window Size"
        case .customPrompt:  return "Custom Prompts"
        case .favoriteTools: return "Favorite Tools"
        case .aiProvider:    return "AI Provider"
        }
    }
}

struct SettingsView: View {
    /// Slice to render. `.all` (default) shows every section — used by the system
    /// ⌘, scene. The menu items pass a single section to focus the window.
    var section: SettingsSection = .all

    @AppStorage("selectedProvider") private var selectedProvider = AIProviderType.groq.rawValue
    @AppStorage("uiScale")          private var uiScaleRaw       = UIScale.small.rawValue
    @ObservedObject private var promptStore = PromptStore.shared
    @ObservedObject private var toolsStore  = FavoriteToolsStore.shared
    @State private var apiKey = ""
    @State private var ollamaAvailable = false
    @State private var saved = false
    @State private var newCustomPrompt = ""
    /// Which favorite-tools tab is showing. `.general` = the shared list; a category
    /// case = that file type's own list (with its Use-General toggle).
    @State private var favTab: FavTab = .general

    /// Selection for the Favorite Tools tab picker.
    private enum FavTab: Hashable {
        case general
        case category(FileCategory)
    }

    private var selectedType: AIProviderType {
        AIProviderType(rawValue: selectedProvider) ?? .groq
    }

    /// Whether a given section should render under the current scope.
    private func shows(_ s: SettingsSection) -> Bool { section == .all || section == s }

    var body: some View {
        Form {
            if shows(.windowSize) {
            Section("Window Size") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(UIScale.allCases, id: \.rawValue) { scale in
                            let selected = uiScaleRaw == scale.rawValue
                            Button {
                                uiScaleRaw = scale.rawValue
                            } label: {
                                VStack(spacing: 4) {
                                    Text(scale.label)
                                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                    Text(scale.sizeHint)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected
                                              ? Color.accentColor.opacity(0.15)
                                              : Color.secondary.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selected ? Color.accentColor : .clear,
                                                              lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Takes effect on the next drag.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            }

            if shows(.customPrompt) {
            Section(header: Text("Custom Prompts"),
                    footer: Text("These appear in the Custom tab when you drop a file. Tap one to run it against the file.")
                        .font(.caption2)
                        .foregroundColor(.secondary)) {
                if promptStore.customPrompts.isEmpty {
                    Text("No custom prompts yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(promptStore.customPrompts, id: \.self) { prompt in
                        HStack {
                            Text(prompt)
                                .font(.system(size: 13))
                                .lineLimit(2)
                            Spacer()
                            Button(role: .destructive) {
                                promptStore.removeCustom(prompt)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                            .help("Delete prompt")
                        }
                    }
                }

                HStack {
                    TextField("Add a custom prompt…", text: $newCustomPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCustomPrompt)
                    Button("Add", action: addCustomPrompt)
                        .disabled(newCustomPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            }

            if shows(.favoriteTools) {
            Section(header: Text("Favorite Tools"),
                    footer: Text("Drop a file, then open it in one of these apps with a click — or press ⌥1…⌥9. Up to 9 apps per list. Each file type can keep its own apps or use your General list.")
                        .font(.caption2)
                        .foregroundColor(.secondary)) {
                Picker("", selection: $favTab) {
                    Text("General").tag(FavTab.general)
                    ForEach(FileCategory.allCases, id: \.self) { c in
                        Text(c.title).tag(FavTab.category(c))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, 4)

                favoriteToolsBody
            }
            }

            if shows(.aiProvider) {
            Section(header: Text("AI Provider"),
                    footer: Text("* with average document sizes")
                        .font(.caption2)
                        .foregroundColor(.secondary)) {
                VStack(spacing: 6) {
                    ForEach(AIProviderType.allCases, id: \.rawValue) { type in
                        ProviderRow(
                            type: type,
                            isSelected: selectedProvider == type.rawValue
                        ) {
                            selectedProvider = type.rawValue
                            apiKey = KeychainManager.shared.load(
                                service: keychainService(for: selectedType)
                            ) ?? ""
                            saved = false
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if selectedType != .ollama {
                Section("API Key (stored securely in Keychain)") {
                    SecureField(placeholder(for: selectedType), text: $apiKey)

                    HStack {
                        Button("Save Key") {
                            KeychainManager.shared.save(
                                key: apiKey.trimmingCharacters(in: .whitespaces),
                                service: keychainService(for: selectedType)
                            )
                            saved = true
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                        if saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }

                        Spacer()

                        switch selectedType {
                        case .groq:
                            Link("Get a free Groq key →", destination: URL(string: "https://console.groq.com")!)
                                .font(.caption)
                        case .gemini:
                            Link("Get a Gemini key →", destination: URL(string: "https://aistudio.google.com/apikey")!)
                                .font(.caption)
                        case .anthropic:
                            Link("Get an Anthropic key →", destination: URL(string: "https://console.anthropic.com")!)
                                .font(.caption)
                        case .openai:
                            Link("Get an OpenAI key →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                .font(.caption)
                        case .ollama:
                            EmptyView()
                        }
                    }
                }
            } else {
                Section("Ollama (Local)") {
                    HStack {
                        Circle()
                            .fill(ollamaAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(ollamaAvailable ? "Ollama is running" : "Ollama not detected")
                            .font(.caption)
                    }
                    Link("Download Ollama →", destination: URL(string: "https://ollama.ai")!)
                        .font(.caption)
                    Text("After installing, run: ollama pull llama3.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .task { ollamaAvailable = await isOllamaRunning() }
            }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            apiKey = KeychainManager.shared.load(service: keychainService(for: selectedType)) ?? ""
        }
    }

    /// Body of the Favorite Tools section for the selected tab. The General tab shows
    /// just its list; a category tab shows a Use-General toggle, then either a note
    /// (deferring) or that category's own editable list.
    @ViewBuilder private var favoriteToolsBody: some View {
        switch favTab {
        case .general:
            favoriteList(for: nil)
        case .category(let c):
            Toggle("Use General favorites", isOn: Binding(
                get: { toolsStore.useGeneral(for: c) },
                set: { toolsStore.setUseGeneral($0, for: c) }
            ))
            if toolsStore.useGeneral(for: c) {
                Text("\(c.title) files use your General favorites.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                favoriteList(for: c)
            }
        }
    }

    /// The editable favorites list for a scope (`nil` = General): icon + name + ⌥N +
    /// remove, drag-to-reorder, and an Add button capped at `maxTools`.
    @ViewBuilder private func favoriteList(for category: FileCategory?) -> some View {
        let tools = toolsStore.tools(for: category)
        if tools.isEmpty {
            Text("No favorite apps yet.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                HStack(spacing: 10) {
                    Image(nsImage: toolsStore.icon(for: tool))
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(tool.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Text("⌥\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Button(role: .destructive) {
                        toolsStore.remove(tool, from: category)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .help("Remove \(tool.name)")
                }
            }
            .onMove { toolsStore.move(from: $0, to: $1, in: category) }
        }

        Button {
            addTool(to: category)
        } label: {
            Label("Add App…", systemImage: "plus")
        }
        .disabled(toolsStore.tools(for: category).count >= FavoriteToolsStore.maxTools)
    }

    private func addCustomPrompt() {
        let t = newCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        promptStore.addCustom(t)
        newCustomPrompt = ""
    }

    /// Pick a .app bundle to add to a favorites list (`nil` = General).
    private func addTool(to category: FileCategory?) {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            toolsStore.add(appURL: url, to: category)
        }
    }

    private func keychainService(for type: AIProviderType) -> String {
        switch type {
        case .groq:      return "com.aidrop.groq"
        case .gemini:    return "com.aidrop.gemini"
        case .anthropic: return "com.aidrop.anthropic"
        case .openai:    return "com.aidrop.openai"
        case .ollama:    return "com.aidrop.ollama"
        }
    }

    private func placeholder(for type: AIProviderType) -> String {
        switch type {
        case .groq:      return "gsk_..."
        case .gemini:    return "AIza..."
        case .anthropic: return "sk-ant-..."
        case .openai:    return "sk-..."
        case .ollama:    return ""
        }
    }
}

/// Checks whether Ollama is running by pinging its health endpoint.
/// Uses proper async/await instead of a blocking semaphore.
private func isOllamaRunning() async -> Bool {
    guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
    var request = URLRequest(url: url, timeoutInterval: 1.5)
    request.httpMethod = "GET"
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
        return false
    }
}
