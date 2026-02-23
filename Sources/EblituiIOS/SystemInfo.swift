import Foundation

/// A system-specific button with display name and bit position
public struct ButtonInfo: Codable {
    public let name: String
    public let id: Int

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "ID"
    }
}

/// Core option type matching Go CoreOptionType constants
public enum CoreOptionType: Int, Codable {
    case bool = 0
    case select = 1
    case range = 2
}

/// A configurable core setting
public struct CoreOption: Codable {
    public let key: String
    public let label: String
    public let description: String
    public let type: CoreOptionType
    public let defaultValue: String
    public let values: [String]?
    public let min: Int
    public let max: Int
    public let step: Int
    public let category: String
    public let perGame: Bool

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case label = "Label"
        case description = "Description"
        case type = "Type"
        case defaultValue = "Default"
        case values = "Values"
        case min = "Min"
        case max = "Max"
        case step = "Step"
        case category = "Category"
        case perGame = "PerGame"
    }
}

/// System metadata decoded from the Go bridge's SystemInfoJSON
public struct SystemInfo: Codable {
    public let name: String
    public let consoleName: String
    public let extensions: [String]
    public let screenWidth: Int
    public let maxScreenHeight: Int
    public let aspectRatio: Double
    public let sampleRate: Int
    public let buttons: [ButtonInfo]
    public let players: Int
    public let coreOptions: [CoreOption]?
    public let rdbName: String
    public let thumbnailRepo: String
    public let dataDirName: String
    public let consoleID: Int
    public let coreName: String
    public let coreVersion: String
    public let serializeSize: Int

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case consoleName = "ConsoleName"
        case extensions = "Extensions"
        case screenWidth = "ScreenWidth"
        case maxScreenHeight = "MaxScreenHeight"
        case aspectRatio = "AspectRatio"
        case sampleRate = "SampleRate"
        case buttons = "Buttons"
        case players = "Players"
        case coreOptions = "CoreOptions"
        case rdbName = "RDBName"
        case thumbnailRepo = "ThumbnailRepo"
        case dataDirName = "DataDirName"
        case consoleID = "ConsoleID"
        case coreName = "CoreName"
        case coreVersion = "CoreVersion"
        case serializeSize = "SerializeSize"
    }
}
