import SwiftUI
import UniformTypeIdentifiers

/// Helper for loading game artwork
public enum ArtworkLoader {
    public static func loadImage(for crc: String) -> UIImage? {
        let artPath = StoragePaths.artworkPath(for: crc)
        return UIImage(contentsOfFile: artPath)
    }
}

/// Game library view showing all games
public struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingFilePicker = false
    @State private var showingSettings = false

    /// Allowed file types for ROM import (from SystemInfo extensions + archive types)
    private var romContentTypes: [UTType] {
        let info = EmulatorBridge.systemInfo
        var types: [UTType] = []
        for ext in info.extensions {
            // Remove leading dot if present
            let cleanExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
            types.append(UTType(filenameExtension: cleanExt) ?? .data)
        }
        // Always allow common archive formats
        types.append(.zip)
        types.append(.gzip)
        types.append(UTType(filenameExtension: "7z") ?? .data)
        types.append(UTType(filenameExtension: "rar") ?? .data)
        return types
    }

    /// Calculate grid columns based on available width (2-4 columns)
    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 16
        let columnCount: Int
        if width < 450 {
            columnCount = 2
        } else if width < 1000 {
            columnCount = 3
        } else {
            columnCount = 4
        }
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if appState.library.games.isEmpty {
                    emptyLibraryView
                } else if appState.config.library.viewMode == .list {
                    gameListView
                } else {
                    gameGridView
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: romContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    handleROMImport(urls: urls)
                case .failure(let error):
                    Log.romImport.error("File picker error: \(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .searchable(text: $appState.librarySearchText, prompt: "Search games")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Games")
                .font(.title2)
                .foregroundColor(.gray)

            Text("Tap + to import ROM files")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))

            Button(action: { showingFilePicker = true }) {
                Label("Import ROMs", systemImage: "plus.circle.fill")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 20)
        }
    }

    private var gameGridView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns(for: geometry.size.width), spacing: 16) {
                        ForEach(sortedGames) { game in
                            GameGridItem(game: game)
                                .id(game.crc32)
                                .onTapGesture {
                                    appState.libraryScrollPosition = game.crc32
                                    appState.navigateToDetail(gameCRC: game.crc32)
                                }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if let position = appState.libraryScrollPosition {
                        proxy.scrollTo(position, anchor: .center)
                    }
                }
            }
        }
    }

    private var gameListView: some View {
        ScrollViewReader { proxy in
            List(sortedGames) { game in
                GameListItem(game: game)
                    .id(game.crc32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.libraryScrollPosition = game.crc32
                        appState.navigateToDetail(gameCRC: game.crc32)
                    }
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .onAppear {
                if let position = appState.libraryScrollPosition {
                    proxy.scrollTo(position, anchor: .center)
                }
            }
        }
    }

    private var sortedGames: [GameEntry] {
        let sorted = appState.library.sortedGames(by: appState.config.library.sortBy)
        if appState.librarySearchText.isEmpty {
            return sorted
        }
        return sorted.filter { game in
            game.displayName.localizedCaseInsensitiveContains(appState.librarySearchText) ||
            game.name.localizedCaseInsensitiveContains(appState.librarySearchText)
        }
    }

    // MARK: - ROM Import

    private func handleROMImport(urls: [URL]) {
        for url in urls {
            importROM(from: url)
        }
    }

    private func importROM(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let info = EmulatorBridge.systemInfo

        do {
            // Ensure directories exist
            try StoragePaths.ensureDirectoriesExist()

            // Extract ROM from archive and store as {CRC32}.{ext}
            guard let importResult = EmulatorBridge.extractAndStoreROM(
                srcPath: url.path,
                destDir: StoragePaths.romsDirectory.path
            ) else {
                Log.romImport.error("Failed to extract ROM: \(url.lastPathComponent)")
                return
            }

            let crcString = importResult.crc

            // Check if already in library
            if appState.library.games[crcString] != nil {
                return
            }

            // Use ROM filename from archive as fallback name
            var name = importResult.name
            var displayName = cleanDisplayName(name)
            var region = extractRegion(from: name)

            // Override with RDB metadata if available
            if let crc32 = UInt32(crcString, radix: 16),
               let rdbGame = appState.lookupGame(crc32: crc32) {
                name = rdbGame.name
                displayName = rdbGame.displayName
                region = rdbGame.region
            }

            // Create library entry - file stored as {CRC32}.{ext}
            let ext = info.extensions.first ?? ""
            let entry = GameEntry(
                crc32: crcString,
                file: crcString + ext,
                name: name,
                displayName: displayName,
                region: region
            )

            // Add to library
            appState.library.addGame(entry)

            // Download artwork using No-Intro name from RDB
            if let crc32 = UInt32(crcString, radix: 16),
               let rdbGame = appState.lookupGame(crc32: crc32) {
                Task {
                    if await appState.artworkDownloader.download(for: crcString, gameName: rdbGame.name) {
                        appState.artworkVersion += 1
                    }
                }
            }

        } catch {
            Log.romImport.error("Failed to import ROM '\(url.lastPathComponent)': \(error.localizedDescription)")
        }
    }

    /// Remove parenthetical info from name (region, version, etc.)
    private func cleanDisplayName(_ name: String) -> String {
        if let range = name.range(of: " (") {
            return String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    /// Extract region from No-Intro style name
    private func extractRegion(from name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("(usa") || lower.contains("(us)") || lower.contains(", usa)") {
            return "us"
        }
        if lower.contains("(europe") || lower.contains("(eu)") || lower.contains(", europe)") {
            return "eu"
        }
        if lower.contains("(japan") || lower.contains("(jp)") || lower.contains(", japan)") {
            return "jp"
        }
        return ""
    }
}

/// Grid item for a single game
struct GameGridItem: View {
    @EnvironmentObject var appState: AppState
    let game: GameEntry
    @State private var artworkImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))

                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }

                if game.missing {
                    Color.red.opacity(0.5)
                        .cornerRadius(8)

                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            // Title
            Text(game.displayName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            artworkImage = ArtworkLoader.loadImage(for: game.crc32)
        }
        .onChange(of: appState.artworkVersion) { _, _ in
            artworkImage = ArtworkLoader.loadImage(for: game.crc32)
        }
    }
}

/// List item for a single game
struct GameListItem: View {
    @EnvironmentObject var appState: AppState
    let game: GameEntry
    @State private var artworkImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))

                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }

                if game.missing {
                    Color.red.opacity(0.5)
                        .cornerRadius(6)
                }
            }
            .frame(width: 50, height: 50)

            // Title and region
            VStack(alignment: .leading, spacing: 4) {
                Text(game.displayName)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(regionDisplayName(game.region))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
        .onAppear {
            artworkImage = ArtworkLoader.loadImage(for: game.crc32)
        }
        .onChange(of: appState.artworkVersion) { _, _ in
            artworkImage = ArtworkLoader.loadImage(for: game.crc32)
        }
    }

    private func regionDisplayName(_ region: String) -> String {
        switch region.lowercased() {
        case "us", "usa": return "USA"
        case "eu", "europe": return "Europe"
        case "jp", "japan": return "Japan"
        default: return region.isEmpty ? "Unknown" : region.uppercased()
        }
    }
}
