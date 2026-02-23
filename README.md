# EblituiIOS

A shared iOS frontend framework for retro console emulators. Provides a complete SwiftUI application shell - library management, game detail views, settings, Metal rendering, audio, touch controls, gamepad support, save states, and SRAM persistence - so that individual emulator cores only need to implement a thin bridge layer.

## Requirements

- iOS 17.0+
- Swift 5.9+
- Emulator core built as an XCFramework via gomobile

## Integration

Each emulator provides two conformances:

### EmulatorEngine

Instance-level emulator operations. Wraps the gomobile-generated framework calls for a single emulation session.

```swift
class MyEmulatorEngine: EmulatorEngine {
    func loadROM(path: String) -> Bool { ... }
    func runFrame() { ... }
    func getFrameBuffer() -> FrameData? { ... }
    func getAudioSamples() -> Data? { ... }
    func setInput(player: Int, buttons: Int) { ... }
    // ... save states, SRAM, options
}
```

### EmulatorBridgeProvider

Static factory operations. Provides system metadata and creates engine instances.

```swift
struct MyBridgeProvider: EmulatorBridgeProvider {
    static var systemInfo: SystemInfo { ... }
    static func createEngine() -> EmulatorEngine { ... }
    static func crc32(ofPath path: String) -> UInt32? { ... }
    static func detectRegion(path: String) -> Int { ... }
    static func extractAndStoreROM(srcPath: String, destDir: String) -> ROMImportResult? { ... }
}
```

### App Entry Point

Register the provider at launch and hand off to the shared ContentView:

```swift
import EblituiIOS

@main
struct MyApp: App {
    init() {
        EmulatorBridge.register(MyBridgeProvider.self)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Package Structure

```
Sources/EblituiIOS/
  App/            - AppState, ContentView (navigation)
  Controls/       - Touch controls overlay
  Emulator/       - EmulatorBridge protocol, AudioEngine, MetalRenderer
  Metadata/       - ROM database parsing, artwork downloading
  Storage/        - Library, save states, SRAM, config persistence
  Utilities/      - Logging
  Views/          - Library, game detail, gameplay, settings views
  SystemInfo.swift
```

## License

See repository root for license information.
