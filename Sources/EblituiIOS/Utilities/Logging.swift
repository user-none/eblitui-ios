import Foundation
import os.log

/// Centralized logging for the app using os.log
public enum Log {
    /// Storage operations (library, config, save states)
    public static let storage = Logger(subsystem: "com.eblitui", category: "storage")

    /// Emulator operations
    public static let emulator = Logger(subsystem: "com.eblitui", category: "emulator")

    /// Network operations (RDB download, artwork)
    public static let network = Logger(subsystem: "com.eblitui", category: "network")

    /// ROM import operations
    public static let romImport = Logger(subsystem: "com.eblitui", category: "import")
}
