import Foundation

/// Manages save states and SRAM for games
public class SaveStateManager {
    private var currentGameCRC: String?

    public init() {}

    /// Set the current game context
    public func setGame(crc: String) {
        currentGameCRC = crc
    }

    // MARK: - Resume State

    /// Save resume state from emulator
    public func saveResumeState(data: Data) throws {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }

        try StoragePaths.ensureSaveDirectoryExists(for: crc)
        let path = StoragePaths.resumeStatePath(for: crc)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load resume state
    public func loadResumeState() throws -> Data {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }

        let path = StoragePaths.resumeStatePath(for: crc)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SaveStateError.stateNotFound
        }

        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Check if resume state exists
    public func hasResumeState() -> Bool {
        guard let crc = currentGameCRC else { return false }
        return FileManager.default.fileExists(atPath: StoragePaths.resumeStatePath(for: crc))
    }

    // MARK: - SRAM

    /// Save SRAM data
    public func saveSRAM(data: Data) throws {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }

        try StoragePaths.ensureSaveDirectoryExists(for: crc)
        let path = StoragePaths.sramPath(for: crc)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load SRAM data
    public func loadSRAM() throws -> Data {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }

        let path = StoragePaths.sramPath(for: crc)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SaveStateError.sramNotFound
        }

        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Check if SRAM exists
    public func hasSRAM() -> Bool {
        guard let crc = currentGameCRC else { return false }
        return FileManager.default.fileExists(atPath: StoragePaths.sramPath(for: crc))
    }

    // MARK: - Manual Save Slots

    /// Save to a numbered slot (0-9)
    public func saveToSlot(_ slot: Int, data: Data) throws {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }
        guard slot >= 0 && slot < 10 else {
            throw SaveStateError.invalidSlot
        }

        try StoragePaths.ensureSaveDirectoryExists(for: crc)
        let path = slotPath(for: crc, slot: slot)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load from a numbered slot
    public func loadFromSlot(_ slot: Int) throws -> Data {
        guard let crc = currentGameCRC else {
            throw SaveStateError.noGameSet
        }
        guard slot >= 0 && slot < 10 else {
            throw SaveStateError.invalidSlot
        }

        let path = slotPath(for: crc, slot: slot)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SaveStateError.stateNotFound
        }

        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Check if a slot has a save
    public func hasSlotSave(_ slot: Int) -> Bool {
        guard let crc = currentGameCRC else { return false }
        guard slot >= 0 && slot < 10 else { return false }
        return FileManager.default.fileExists(atPath: slotPath(for: crc, slot: slot))
    }

    private func slotPath(for crc: String, slot: Int) -> String {
        StoragePaths.saveDirectory(for: crc)
            .appendingPathComponent("slot\(slot).state")
            .path
    }
}

public enum SaveStateError: Error, LocalizedError {
    case noGameSet
    case stateNotFound
    case sramNotFound
    case invalidSlot

    public var errorDescription: String? {
        switch self {
        case .noGameSet:
            return "No game is currently set"
        case .stateNotFound:
            return "Save state not found"
        case .sramNotFound:
            return "SRAM data not found"
        case .invalidSlot:
            return "Invalid save slot"
        }
    }
}
