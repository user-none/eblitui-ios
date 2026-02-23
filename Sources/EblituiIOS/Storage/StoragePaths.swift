import Foundation

/// Storage paths for app data, using SystemInfo for directory naming
public enum StoragePaths {
    /// Documents directory (visible in Files app)
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Application Support directory (hidden from user)
    public static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Documents paths

    /// ROMs directory in Documents
    public static var romsDirectory: URL {
        documentsDirectory.appendingPathComponent("roms", isDirectory: true)
    }

    /// Library JSON file path
    public static var libraryPath: String {
        documentsDirectory.appendingPathComponent("library.json").path
    }

    // MARK: - Application Support paths

    /// Config JSON file path
    public static var configPath: String {
        appSupportDirectory.appendingPathComponent("config.json").path
    }

    /// Metadata directory
    public static var metadataDirectory: URL {
        appSupportDirectory.appendingPathComponent("metadata", isDirectory: true)
    }

    /// RDB file path (uses dataDirName from SystemInfo)
    public static var rdbPath: String {
        let info = EmulatorBridge.systemInfo
        return metadataDirectory.appendingPathComponent("\(info.dataDirName).rdb").path
    }

    /// Saves directory
    public static var savesDirectory: URL {
        appSupportDirectory.appendingPathComponent("saves", isDirectory: true)
    }

    /// Artwork directory
    public static var artworkDirectory: URL {
        appSupportDirectory.appendingPathComponent("artwork", isDirectory: true)
    }

    // MARK: - Per-game paths

    /// Save directory for a specific game
    public static func saveDirectory(for crc: String) -> URL {
        savesDirectory.appendingPathComponent(crc, isDirectory: true)
    }

    /// Resume state path for a game
    public static func resumeStatePath(for crc: String) -> String {
        saveDirectory(for: crc).appendingPathComponent("resume.state").path
    }

    /// SRAM path for a game
    public static func sramPath(for crc: String) -> String {
        saveDirectory(for: crc).appendingPathComponent("sram.bin").path
    }

    /// Artwork path for a game
    public static func artworkPath(for crc: String) -> String {
        artworkDirectory.appendingPathComponent("\(crc).png").path
    }

    // MARK: - Directory creation

    /// Ensures all required directories exist
    public static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        let directories = [
            romsDirectory,
            metadataDirectory,
            savesDirectory,
            artworkDirectory
        ]

        for dir in directories {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    /// Ensures save directory exists for a game
    public static func ensureSaveDirectoryExists(for crc: String) throws {
        let dir = saveDirectory(for: crc)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
