import Foundation

/// Application configuration
public struct Config: Codable {
    public var version: Int = 1
    public var audio: AudioConfig = AudioConfig()
    public var library: LibraryConfig = LibraryConfig()
    public var coreOptions: [String: String] = [:]

    public init() {}

    public struct AudioConfig: Codable {
        public var mute: Bool = false
        public init() {}
    }

    public struct LibraryConfig: Codable {
        public var viewMode: ViewMode = .icon
        public var sortBy: Library.SortMethod = .title

        public init() {}

        public enum ViewMode: String, Codable, CaseIterable {
            case icon
            case list

            public var displayName: String {
                switch self {
                case .icon: return "Icons"
                case .list: return "List"
                }
            }
        }
    }

    // MARK: - Persistence

    public static func load() -> Config? {
        let path = StoragePaths.configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Config.self, from: data)
        } catch {
            Log.storage.error("Failed to decode config: \(error.localizedDescription)")
            return nil
        }
    }

    public func save() {
        do {
            // Ensure directory exists
            let dir = URL(fileURLWithPath: StoragePaths.configPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: URL(fileURLWithPath: StoragePaths.configPath))
        } catch {
            Log.storage.error("Failed to save config: \(error.localizedDescription)")
        }
    }
}
