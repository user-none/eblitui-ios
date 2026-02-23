import SwiftUI

/// Settings view for app configuration
public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let info = EmulatorBridge.systemInfo

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Core options from SystemInfo (dynamic)
                coreOptionsSection

                // Audio settings
                Section("Audio") {
                    Toggle("Mute", isOn: Binding(
                        get: { appState.config.audio.mute },
                        set: { newValue in
                            appState.config.audio.mute = newValue
                            appState.saveConfig()
                        }
                    ))
                }

                // Library settings
                Section("Library") {
                    Picker("View Mode", selection: Binding(
                        get: { appState.config.library.viewMode },
                        set: { newValue in
                            appState.config.library.viewMode = newValue
                            appState.saveConfig()
                        }
                    )) {
                        ForEach(Config.LibraryConfig.ViewMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Sort By", selection: Binding(
                        get: { appState.config.library.sortBy },
                        set: { newValue in
                            appState.config.library.sortBy = newValue
                            appState.saveConfig()
                        }
                    )) {
                        ForEach(Library.SortMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                }

                // Database section
                Section("Database") {
                    HStack {
                        Text("Game Database")
                        Spacer()
                        if appState.isRDBDownloading {
                            ProgressView()
                        } else if appState.isRDBLoaded {
                            Text("Loaded")
                                .foregroundColor(.green)
                        } else {
                            Text("Not Downloaded")
                                .foregroundColor(.gray)
                        }
                    }

                    Button(action: downloadRDB) {
                        HStack {
                            Text(appState.isRDBLoaded ? "Update Database" : "Download Database")
                            Spacer()
                            if appState.isRDBDownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(appState.isRDBDownloading)

                    Button(action: downloadArtwork) {
                        HStack {
                            Text("Download Missing Artwork")
                            Spacer()
                            if appState.isArtworkDownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(appState.isArtworkDownloading)
                }

                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("Emulator")
                        Spacer()
                        Text(info.coreName)
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("System")
                        Spacer()
                        Text(info.consoleName)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Dynamic Core Options

    @ViewBuilder
    private var coreOptionsSection: some View {
        if let options = info.coreOptions, !options.isEmpty {
            // Group options by category
            let categories = orderedCategories(from: options)

            ForEach(categories, id: \.self) { category in
                let categoryOptions = options.filter { $0.category == category }
                Section(category) {
                    ForEach(categoryOptions, id: \.key) { option in
                        coreOptionView(for: option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coreOptionView(for option: CoreOption) -> some View {
        switch option.type {
        case .bool:
            Toggle(option.label, isOn: Binding(
                get: {
                    let value = appState.config.coreOptions[option.key] ?? option.defaultValue
                    return value == "true"
                },
                set: { newValue in
                    appState.config.coreOptions[option.key] = newValue ? "true" : "false"
                    appState.saveConfig()
                }
            ))

        case .select:
            if let values = option.values {
                Picker(option.label, selection: Binding(
                    get: {
                        appState.config.coreOptions[option.key] ?? option.defaultValue
                    },
                    set: { newValue in
                        appState.config.coreOptions[option.key] = newValue
                        appState.saveConfig()
                    }
                )) {
                    ForEach(values, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            }

        case .range:
            // Range options not commonly used in iOS, show as text for now
            HStack {
                Text(option.label)
                Spacer()
                Text(appState.config.coreOptions[option.key] ?? option.defaultValue)
                    .foregroundColor(.gray)
            }
        }
    }

    private func orderedCategories(from options: [CoreOption]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for option in options {
            if !seen.contains(option.category) {
                seen.insert(option.category)
                result.append(option.category)
            }
        }
        return result
    }

    private func downloadRDB() {
        Task {
            await appState.downloadRDB()
        }
    }

    private func downloadArtwork() {
        Task {
            await appState.downloadMissingArtwork()
        }
    }
}
