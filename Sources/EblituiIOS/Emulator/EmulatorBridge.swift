import Foundation

/// Bundles pixel data with layout information, mirroring the standalone
/// renderer which receives pixels, stride, and activeHeight together.
public struct FrameData {
    public let pixels: Data
    public let stride: Int
    public let activeHeight: Int

    public init(pixels: Data, stride: Int, activeHeight: Int) {
        self.pixels = pixels
        self.stride = stride
        self.activeHeight = activeHeight
    }
}

/// Result from extracting and storing a ROM
public struct ROMImportResult {
    public let crc: String
    public let name: String

    public init(crc: String, name: String) {
        self.crc = crc
        self.name = name
    }
}

/// Protocol for instance-level emulator operations.
/// Each emulator core provides a concrete implementation.
public protocol EmulatorEngine: AnyObject {
    var isLoaded: Bool { get }
    var fps: Int { get }
    var hasSaveStates: Bool { get }
    var hasSRAM: Bool { get }

    func loadROM(path: String) -> Bool
    func loadROM(path: String, region: Int) -> Bool
    func unload()
    func runFrame()
    func getFrameBuffer() -> FrameData?
    func getAudioSamples() -> Data?
    func setInput(player: Int, buttons: Int)
    func setOption(key: String, value: String)
    func serialize() -> Data?
    func deserialize(data: Data) -> Bool
    func getSRAM() -> Data?
    func setSRAM(data: Data)
}

/// Protocol for static/factory emulator operations.
/// Each emulator core registers a provider at app launch.
public protocol EmulatorBridgeProvider {
    static var systemInfo: SystemInfo { get }
    static func createEngine() -> EmulatorEngine
    static func crc32(ofPath path: String) -> UInt32?
    static func detectRegion(path: String) -> Int
    static func extractAndStoreROM(srcPath: String, destDir: String) -> ROMImportResult?
}

/// Facade that preserves existing call sites.
/// Call `EmulatorBridge.register(_:)` once at app launch before
/// accessing any other member.
public enum EmulatorBridge {
    private static var providerType: EmulatorBridgeProvider.Type?

    private static var provider: EmulatorBridgeProvider.Type {
        guard let p = providerType else {
            fatalError("EmulatorBridge: no provider registered. Call register(_:) at app launch.")
        }
        return p
    }

    /// Register the concrete bridge provider. Must be called before any other access.
    public static func register(_ providerType: EmulatorBridgeProvider.Type) {
        self.providerType = providerType
    }

    /// Get system info from the registered provider
    public static var systemInfo: SystemInfo {
        provider.systemInfo
    }

    /// Create a new emulator engine instance
    public static func createEngine() -> EmulatorEngine {
        provider.createEngine()
    }

    /// Calculate CRC32 of ROM file
    public static func crc32(ofPath path: String) -> UInt32? {
        provider.crc32(ofPath: path)
    }

    /// Detect region for ROM file
    public static func detectRegion(path: String) -> Int {
        provider.detectRegion(path: path)
    }

    /// Extract ROM from archive and store as {CRC32}.{ext}
    public static func extractAndStoreROM(srcPath: String, destDir: String) -> ROMImportResult? {
        provider.extractAndStoreROM(srcPath: srcPath, destDir: destDir)
    }
}
