import Foundation

/// Downloads game artwork from libretro thumbnails repository
public class ArtworkDownloader {
    // Network limits
    private static let downloadTimeout: TimeInterval = 10
    private static let maxArtworkSize = 2 * 1024 * 1024  // 2MB

    // Artwork base URL constructed from SystemInfo
    private static var baseURL: String {
        let info = EmulatorBridge.systemInfo
        return "https://raw.githubusercontent.com/libretro-thumbnails/\(info.thumbnailRepo)/master/Named_Boxarts/"
    }

    // Custom URLSession with timeout
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.downloadTimeout
        config.timeoutIntervalForResource = Self.downloadTimeout
        return URLSession(configuration: config)
    }()

    public init() {}

    /// Download artwork for a game
    /// Returns true if artwork was successfully downloaded
    @discardableResult
    public func download(for crc: String, gameName: String) async -> Bool {
        // Format the game name for the URL
        let encodedName = encodeForURL(gameName)

        guard let url = URL(string: "\(Self.baseURL)\(encodedName).png") else {
            return false
        }

        do {
            let (data, response) = try await urlSession.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            // Enforce size limit
            guard data.count <= Self.maxArtworkSize else {
                Log.network.debug("Artwork too large for \(gameName): \(data.count) bytes")
                return false
            }

            // Ensure artwork directory exists
            try StoragePaths.ensureDirectoriesExist()

            // Save artwork
            let artPath = StoragePaths.artworkPath(for: crc)
            try data.write(to: URL(fileURLWithPath: artPath))
            return true

        } catch {
            Log.network.debug("Artwork download failed for \(gameName): \(error.localizedDescription)")
            return false
        }
    }

    /// Encode game name for libretro thumbnail URL
    private func encodeForURL(_ name: String) -> String {
        var result = name

        // Replace characters that are invalid in filenames or URLs
        let replacements: [(String, String)] = [
            ("&", "_")
        ]

        for (old, new) in replacements {
            result = result.replacingOccurrences(of: old, with: new)
        }

        // URL encode the result
        return result.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }
}
