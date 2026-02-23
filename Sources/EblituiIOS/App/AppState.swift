import SwiftUI
import Combine

/// Represents the current screen in the app navigation
public enum AppScreen: Equatable {
    case library
    case settings
    case detail(gameCRC: String)
    case gameplay(gameCRC: String, resume: Bool)
}

/// Observable app state shared across all views
@MainActor
public class AppState: ObservableObject {
    // MARK: - Navigation

    @Published public var currentScreen: AppScreen = .library

    // MARK: - Data

    @Published public var library: Library
    @Published public var config: Config

    // MARK: - Managers

    public let rdbParser: RDBParser
    public let artworkDownloader: ArtworkDownloader

    // MARK: - RDB State

    @Published public var isRDBLoaded: Bool = false
    @Published public var isRDBDownloading: Bool = false

    // MARK: - Artwork State

    /// Incremented when artwork is downloaded, triggers UI refresh
    @Published public var artworkVersion: Int = 0

    @Published public var isArtworkDownloading: Bool = false

    // MARK: - Library UI State

    /// Search text for library filtering (persists across navigation)
    @Published public var librarySearchText: String = ""

    /// Scroll position in library (game CRC, persists across navigation)
    @Published public var libraryScrollPosition: String?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        // Load or create config
        if let loadedConfig = Config.load() {
            self.config = loadedConfig
        } else {
            self.config = Config()
        }

        // Load or create library
        if let loadedLibrary = Library.load() {
            self.library = loadedLibrary
        } else {
            self.library = Library()
        }

        // Initialize managers
        self.rdbParser = RDBParser()
        self.artworkDownloader = ArtworkDownloader()

        // Forward library changes to trigger view updates
        library.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Load RDB if available
        Task {
            await loadRDBIfAvailable()
        }
    }

    // MARK: - Navigation

    public func navigateToLibrary() {
        currentScreen = .library
    }

    public func navigateToSettings() {
        currentScreen = .settings
    }

    public func navigateToDetail(gameCRC: String) {
        currentScreen = .detail(gameCRC: gameCRC)
    }

    public func launchGame(gameCRC: String, resume: Bool) {
        currentScreen = .gameplay(gameCRC: gameCRC, resume: resume)
    }

    // MARK: - Library Management

    public func saveLibrary() {
        library.save()
    }

    public func saveConfig() {
        config.save()
    }

    public func getGame(crc: String) -> GameEntry? {
        return library.games[crc]
    }

    public func updateGameLastPlayed(crc: String) {
        if var game = library.games[crc] {
            game.lastPlayed = Date().timeIntervalSince1970
            library.games[crc] = game
            saveLibrary()
        }
    }

    // MARK: - RDB Management

    public func loadRDBIfAvailable() async {
        let rdbPath = StoragePaths.rdbPath
        if FileManager.default.fileExists(atPath: rdbPath) {
            do {
                try rdbParser.load(from: rdbPath)
                isRDBLoaded = true
            } catch {
                Log.storage.error("Failed to load RDB: \(error.localizedDescription)")
            }
        } else {
            // Auto-download if not present
            await downloadRDB()
        }
    }

    public func downloadRDB() async {
        guard !isRDBDownloading else { return }

        isRDBDownloading = true
        defer { isRDBDownloading = false }

        do {
            try await rdbParser.downloadAndLoad()
            isRDBLoaded = true
            refreshLibraryMetadata()
        } catch {
            Log.network.error("Failed to download RDB: \(error.localizedDescription)")
        }
    }

    /// Update library entries with metadata from RDB
    private func refreshLibraryMetadata() {
        var updated = false
        for (crc, var game) in library.games {
            if let crc32 = UInt32(crc, radix: 16),
               let rdbGame = rdbParser.lookup(crc32: crc32) {
                game.name = rdbGame.name
                game.displayName = rdbGame.displayName
                game.region = rdbGame.region
                library.games[crc] = game
                updated = true
            }
        }
        if updated {
            saveLibrary()
        }
    }

    public func lookupGame(crc32: UInt32) -> RDBGameInfo? {
        return rdbParser.lookup(crc32: crc32)
    }

    // MARK: - Artwork

    public func downloadMissingArtwork() async {
        guard !isArtworkDownloading else { return }

        isArtworkDownloading = true
        defer { isArtworkDownloading = false }

        for (crc, _) in library.games {
            let artPath = StoragePaths.artworkPath(for: crc)
            if !FileManager.default.fileExists(atPath: artPath) {
                // Use No-Intro name from RDB for artwork lookup
                guard let crc32 = UInt32(crc, radix: 16),
                      let rdbGame = rdbParser.lookup(crc32: crc32) else {
                    continue
                }
                Log.network.debug("Downloading artwork for \(rdbGame.name)")
                if await artworkDownloader.download(for: crc, gameName: rdbGame.name) {
                    artworkVersion += 1
                }
            }
        }
    }
}
