import Foundation

/// Game metadata from the RDB database
public struct RDBGameInfo {
    public let name: String           // Full No-Intro name
    public let description: String
    public let genre: String
    public let developer: String
    public let publisher: String
    public let franchise: String
    public let esrbRating: String
    public let romName: String
    public let releaseMonth: UInt
    public let releaseYear: UInt
    public let size: UInt64
    public let crc32: UInt32
    public let serial: String

    /// Clean display name without region/version info
    public var displayName: String {
        RDBParser.getDisplayName(from: name)
    }

    /// Extracted region code ("us", "eu", "jp", or "")
    public var region: String {
        RDBParser.getRegion(from: name)
    }
}

/// Parser for libretro RDB (RetroDatabase) files
/// The RDB format uses MessagePack encoding
public class RDBParser {
    private var games: [RDBGameInfo] = []
    private var byCRC32: [UInt32: RDBGameInfo] = [:]

    // RDB download URL constructed from SystemInfo
    private static var rdbURL: String {
        let info = EmulatorBridge.systemInfo
        let encoded = info.rdbName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? info.rdbName
        return "https://raw.githubusercontent.com/libretro/libretro-database/master/rdb/\(encoded).rdb"
    }

    // Maximum download size (5MB)
    private static let maxDownloadSize = 5 * 1024 * 1024

    // MessagePack format constants
    private static let mpfFixMap: UInt8 = 0x80
    private static let mpfMap16: UInt8 = 0xde
    private static let mpfMap32: UInt8 = 0xdf
    private static let mpfFixArray: UInt8 = 0x90
    private static let mpfFixStr: UInt8 = 0xa0
    private static let mpfStr8: UInt8 = 0xd9
    private static let mpfStr16: UInt8 = 0xda
    private static let mpfStr32: UInt8 = 0xdb
    private static let mpfBin8: UInt8 = 0xc4
    private static let mpfBin16: UInt8 = 0xc5
    private static let mpfBin32: UInt8 = 0xc6
    private static let mpfUint8: UInt8 = 0xcc
    private static let mpfUint16: UInt8 = 0xcd
    private static let mpfUint32: UInt8 = 0xce
    private static let mpfUint64: UInt8 = 0xcf
    private static let mpfNil: UInt8 = 0xc0

    public var gameCount: Int { games.count }

    public init() {}

    /// Load RDB from file
    public func load(from path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        parse(data: data)
    }

    /// Download and load the RDB
    public func downloadAndLoad() async throws {
        guard let url = URL(string: Self.rdbURL) else {
            throw RDBError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RDBError.downloadFailed
        }

        // Enforce size limit to prevent DoS
        guard data.count <= Self.maxDownloadSize else {
            throw RDBError.fileTooLarge
        }

        // Save to disk
        try StoragePaths.ensureDirectoriesExist()
        try data.write(to: URL(fileURLWithPath: StoragePaths.rdbPath))

        // Parse the data
        parse(data: data)
    }

    /// Lookup a game by CRC32
    public func lookup(crc32: UInt32) -> RDBGameInfo? {
        return byCRC32[crc32]
    }

    /// Parse RDB data
    private func parse(data: Data) {
        games = parseGames(data: data)
        byCRC32 = [:]
        for game in games where game.crc32 != 0 {
            byCRC32[game.crc32] = game
        }
    }

    /// Parse all games from RDB data
    private func parseGames(data: Data) -> [RDBGameInfo] {
        guard data.count >= 0x11 else { return [] }

        var output: [RDBGameInfo] = []
        var pos = 0x10
        var isKey = false
        var key = ""
        var currentGame = GameBuilder()

        while pos < data.count && data[pos] != Self.mpfNil {
            let fieldType = data[pos]
            var value: Data?

            if fieldType < Self.mpfFixMap {
                // Positive fixint - skip
                pos += 1
                continue
            } else if fieldType < Self.mpfFixArray {
                // fixmap - new game entry
                if currentGame.hasData {
                    output.append(currentGame.build())
                }
                currentGame = GameBuilder()
                pos += 1
                isKey = true
                continue
            } else if fieldType < Self.mpfNil {
                // fixstr
                let length = Int(fieldType) - Int(Self.mpfFixStr)
                pos += 1
                guard pos + length <= data.count else { break }
                value = data[pos..<(pos + length)]
                pos += length
            }

            switch fieldType {
            case Self.mpfStr8, Self.mpfStr16, Self.mpfStr32:
                pos += 1
                let lenLen = Int(fieldType) - Int(Self.mpfStr8) + 1
                guard pos + lenLen <= data.count else { break }
                let length = readLength(data: data, pos: pos, size: lenLen)
                pos += lenLen
                guard pos + length <= data.count else { break }
                value = data[pos..<(pos + length)]
                pos += length

            case Self.mpfUint8, Self.mpfUint16, Self.mpfUint32, Self.mpfUint64:
                let pow = Double(fieldType) - 0xC9
                let length = Int(Foundation.pow(2.0, pow)) / 8
                pos += 1
                guard pos + length <= data.count else { break }
                value = data[pos..<(pos + length)]
                pos += length

            case Self.mpfBin8, Self.mpfBin16, Self.mpfBin32:
                pos += 1
                guard pos < data.count else { break }
                let length = Int(data[pos])
                pos += 1
                guard pos + length <= data.count else { break }
                value = data[pos..<(pos + length)]
                pos += length

            case Self.mpfMap16, Self.mpfMap32:
                // Map16/Map32 mark a new game entry (same as fixmap but for 16+ fields)
                if currentGame.hasData {
                    output.append(currentGame.build())
                }
                currentGame = GameBuilder()
                let length = fieldType == Self.mpfMap32 ? 4 : 2
                pos += 1
                guard pos + length <= data.count else { break }
                pos += length
                isKey = true
                continue

            default:
                break
            }

            if let value = value {
                if isKey {
                    key = String(data: value, encoding: .utf8) ?? ""
                } else {
                    currentGame.set(key: key, value: value)
                }
            }
            isKey = !isKey
        }

        // Don't forget the last entry
        if currentGame.hasData {
            output.append(currentGame.build())
        }

        return output
    }

    private func readLength(data: Data, pos: Int, size: Int) -> Int {
        var length = 0
        for i in 0..<size {
            length = (length << 8) | Int(data[pos + i])
        }
        return length
    }

    // MARK: - Static helpers

    /// Extract clean display name from No-Intro name
    public static func getDisplayName(from name: String) -> String {
        if let range = name.range(of: " (") {
            return String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    /// Extract region from No-Intro name
    public static func getRegion(from name: String) -> String {
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
        if lower.contains("(usa, europe)") || lower.contains("(world)") {
            return "us"
        }

        return ""
    }
}

/// Helper for building RDBGameInfo
private struct GameBuilder {
    var name = ""
    var description = ""
    var genre = ""
    var developer = ""
    var publisher = ""
    var franchise = ""
    var esrbRating = ""
    var romName = ""
    var releaseMonth: UInt = 0
    var releaseYear: UInt = 0
    var size: UInt64 = 0
    var crc32: UInt32 = 0
    var serial = ""

    var hasData: Bool {
        !name.isEmpty || crc32 != 0
    }

    mutating func set(key: String, value: Data) {
        switch key {
        case "name":
            name = String(data: value, encoding: .utf8) ?? ""
        case "description":
            description = String(data: value, encoding: .utf8) ?? ""
        case "genre":
            genre = String(data: value, encoding: .utf8) ?? ""
        case "developer":
            developer = String(data: value, encoding: .utf8) ?? ""
        case "publisher":
            publisher = String(data: value, encoding: .utf8) ?? ""
        case "franchise":
            franchise = String(data: value, encoding: .utf8) ?? ""
        case "esrb_rating":
            esrbRating = String(data: value, encoding: .utf8) ?? ""
        case "serial":
            serial = String(data: value, encoding: .utf8) ?? ""
        case "rom_name":
            romName = String(data: value, encoding: .utf8) ?? ""
        case "size":
            size = parseUInt64(value)
        case "releasemonth":
            releaseMonth = UInt(parseUInt64(value))
        case "releaseyear":
            releaseYear = UInt(parseUInt64(value))
        case "crc":
            crc32 = UInt32(parseUInt64(value))
        default:
            break
        }
    }

    private func parseUInt64(_ data: Data) -> UInt64 {
        var result: UInt64 = 0
        for byte in data {
            result = (result << 8) | UInt64(byte)
        }
        return result
    }

    func build() -> RDBGameInfo {
        RDBGameInfo(
            name: name,
            description: description,
            genre: genre,
            developer: developer,
            publisher: publisher,
            franchise: franchise,
            esrbRating: esrbRating,
            romName: romName,
            releaseMonth: releaseMonth,
            releaseYear: releaseYear,
            size: size,
            crc32: crc32,
            serial: serial
        )
    }
}

public enum RDBError: Error, LocalizedError {
    case invalidURL
    case downloadFailed
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid RDB URL"
        case .downloadFailed:
            return "Failed to download RDB"
        case .fileTooLarge:
            return "RDB file exceeds maximum size limit"
        }
    }
}
