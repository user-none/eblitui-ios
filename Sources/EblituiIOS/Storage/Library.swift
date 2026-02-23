import Foundation

/// A game entry in the library
public struct GameEntry: Codable, Identifiable {
    public var id: String { crc32 }

    public let crc32: String
    public var file: String           // ROM filename (relative to roms directory)
    public var name: String           // Full No-Intro name from RDB
    public var displayName: String    // Cleaned name for display
    public var region: String         // "us", "eu", "jp"
    public var missing: Bool          // true if ROM file not found
    public var lastPlayed: TimeInterval  // Unix timestamp
    public var added: TimeInterval       // Unix timestamp when added

    /// Full path to ROM file (computed at runtime to handle container changes)
    public var filePath: String {
        StoragePaths.romsDirectory.appendingPathComponent(file).path
    }

    public init(crc32: String, file: String, name: String, displayName: String, region: String) {
        self.crc32 = crc32
        self.file = file
        self.name = name
        self.displayName = displayName
        self.region = region
        self.missing = false
        self.lastPlayed = 0
        self.added = Date().timeIntervalSince1970
    }
}

/// Game library stored in library.json
public class Library: Codable, ObservableObject {
    public var version: Int
    @Published public var games: [String: GameEntry]

    enum CodingKeys: String, CodingKey {
        case version, games
    }

    public init() {
        self.version = 1
        self.games = [:]
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        games = try container.decode([String: GameEntry].self, forKey: .games)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(games, forKey: .games)
    }

    // MARK: - Persistence

    public static func load() -> Library? {
        let path = StoragePaths.libraryPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Library.self, from: data)
        } catch {
            Log.storage.error("Failed to decode library: \(error.localizedDescription)")
            return nil
        }
    }

    public func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: URL(fileURLWithPath: StoragePaths.libraryPath))
        } catch {
            Log.storage.error("Failed to save library: \(error.localizedDescription)")
        }
    }

    // MARK: - Game management

    public func addGame(_ entry: GameEntry) {
        games[entry.crc32] = entry
        save()
    }

    public func removeGame(crc: String) {
        games.removeValue(forKey: crc)
        save()
    }

    public func sortedGames(by sortMethod: SortMethod) -> [GameEntry] {
        let gamesArray = Array(games.values)
        switch sortMethod {
        case .title:
            return gamesArray.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .lastPlayed:
            return gamesArray.sorted { $0.lastPlayed > $1.lastPlayed }
        case .dateAdded:
            return gamesArray.sorted { $0.added > $1.added }
        }
    }

    public enum SortMethod: String, Codable, CaseIterable {
        case title
        case lastPlayed
        case dateAdded

        public var displayName: String {
            switch self {
            case .title: return "Title"
            case .lastPlayed: return "Last Played"
            case .dateAdded: return "Date Added"
            }
        }
    }
}
