import SwiftUI
import MetalKit
import GameController

/// Main gameplay view with emulator and touch controls
public struct GameplayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    let gameCRC: String
    let resume: Bool

    @State private var buttonMask: Int = 0
    @State private var showPauseMenu = false
    @State private var emulatorManager: EmulatorManager?
    @State private var gamepadObserver: NSObjectProtocol?

    public init(gameCRC: String, resume: Bool) {
        self.gameCRC = gameCRC
        self.resume = resume
    }

    public var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            let dar = Double(EmulatorBridge.systemInfo.screenWidth) / Double(EmulatorBridge.systemInfo.maxScreenHeight) * EmulatorBridge.systemInfo.pixelAspectRatio
            let gameHeight = geometry.size.width / dar

            ZStack {
                Color.black.ignoresSafeArea()

                if isPortrait {
                    VStack(spacing: 0) {
                        if let manager = emulatorManager {
                            MetalEmulatorView(
                                manager: manager,
                                size: CGSize(width: geometry.size.width, height: gameHeight)
                            )
                            .frame(width: geometry.size.width, height: gameHeight)
                        } else {
                            Color.clear.frame(height: gameHeight)
                        }

                        TouchControlsView(
                            buttonMask: $buttonMask,
                            onMenuTap: { showPauseMenu = true }
                        )
                    }
                } else {
                    let fullWidth = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
                    let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                    let fullSize = CGSize(width: fullWidth, height: fullHeight)

                    if let manager = emulatorManager {
                        MetalEmulatorView(
                            manager: manager,
                            size: fullSize
                        )
                        .frame(width: fullWidth, height: fullHeight)
                        .ignoresSafeArea()
                    }

                    TouchControlsView(
                        buttonMask: $buttonMask,
                        onMenuTap: { showPauseMenu = true }
                    )
                    .frame(width: fullWidth, height: fullHeight)
                    .ignoresSafeArea()
                }

                // Pause menu overlay
                if showPauseMenu {
                    PauseMenuView(
                        onResume: { showPauseMenu = false },
                        onLibrary: { exitToLibrary() }
                    )
                }
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            startEmulator()
            setupGamepadObserver()
        }
        .onDisappear {
            stopEmulator()
            removeGamepadObserver()
        }
        .onChange(of: buttonMask) { _, newMask in
            emulatorManager?.setInput(player: 0, buttons: newMask)
        }
        .onChange(of: showPauseMenu) { _, isPaused in
            if isPaused {
                emulatorManager?.pause()
            } else {
                emulatorManager?.resume()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                showPauseMenu = true
            }
        }
    }

    // MARK: - Emulator Lifecycle

    private func startEmulator() {
        guard let game = appState.library.games[gameCRC] else {
            appState.navigateToLibrary()
            return
        }

        let manager = EmulatorManager()
        guard manager.loadROM(path: game.filePath) else {
            appState.navigateToLibrary()
            return
        }

        // Apply stored core options
        manager.applyCoreOptions(appState.config.coreOptions)

        // Load SRAM if available
        manager.loadSRAM(gameCRC: gameCRC)

        // Load resume state if requested
        if resume {
            manager.loadResumeState(gameCRC: gameCRC)
        }

        // Start emulation
        manager.start(muted: appState.config.audio.mute)

        self.emulatorManager = manager

        // Update last played
        appState.updateGameLastPlayed(crc: gameCRC)
    }

    private func stopEmulator() {
        guard let manager = emulatorManager else { return }

        // Save state
        manager.saveResumeState(gameCRC: gameCRC)
        manager.saveSRAM(gameCRC: gameCRC)

        // Stop emulation
        manager.stop()

        emulatorManager = nil
    }

    private func exitToLibrary() {
        showPauseMenu = false
        appState.navigateToLibrary()
    }

    // MARK: - Gamepad Support

    private func setupGamepadObserver() {
        gamepadObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak emulatorManager] _ in
            guard emulatorManager != nil else { return }
            setupGamepadInput()
        }

        // Setup any already connected controller
        setupGamepadInput()
    }

    private func removeGamepadObserver() {
        if let observer = gamepadObserver {
            NotificationCenter.default.removeObserver(observer)
            gamepadObserver = nil
        }
        clearGamepadHandlers()
    }

    private func clearGamepadHandlers() {
        guard let controller = GCController.controllers().first,
              let gamepad = controller.extendedGamepad else {
            return
        }
        gamepad.dpad.valueChangedHandler = nil
        gamepad.buttonA.valueChangedHandler = nil
        gamepad.buttonB.valueChangedHandler = nil
        gamepad.buttonMenu.valueChangedHandler = nil
        controller.extendedGamepad?.buttonOptions?.valueChangedHandler = nil
    }

    private func setupGamepadInput() {
        guard let controller = GCController.controllers().first,
              let gamepad = controller.extendedGamepad else {
            return
        }

        let sysButtons = EmulatorBridge.systemInfo.buttons

        // Build gamepad button mapping based on SystemInfo
        // Map standard gamepad buttons to system button bit positions
        let buttonMap = buildGamepadMapping(sysButtons: sysButtons, gamepad: gamepad)

        // D-pad handler
        gamepad.dpad.valueChangedHandler = { [weak emulatorManager] dpad, _, _ in
            var mask = buildDpadMask(dpad: dpad)
            mask |= buildGamepadButtonMask(gamepad: gamepad, mapping: buttonMap)
            emulatorManager?.setInput(player: 0, buttons: mask)
        }

        // Button handlers - rebuild full mask on any button change
        for (gcButton, _) in buttonMap {
            gcButton.valueChangedHandler = { [weak emulatorManager] _, _, _ in
                var mask = buildDpadMask(dpad: gamepad.dpad)
                mask |= buildGamepadButtonMask(gamepad: gamepad, mapping: buttonMap)
                emulatorManager?.setInput(player: 0, buttons: mask)
            }
        }

        // Menu button as Start
        gamepad.buttonMenu.valueChangedHandler = { [weak emulatorManager] _, _, pressed in
            if pressed {
                if let startBtn = sysButtons.first(where: { $0.name == "Start" }) {
                    var mask = buildDpadMask(dpad: gamepad.dpad)
                    mask |= buildGamepadButtonMask(gamepad: gamepad, mapping: buttonMap)
                    mask |= (1 << startBtn.id)
                    emulatorManager?.setInput(player: 0, buttons: mask)
                }
            }
        }

    }
}

// MARK: - Gamepad Helpers

private func buildDpadMask(dpad: GCControllerDirectionPad) -> Int {
    var mask = 0
    if dpad.up.isPressed { mask |= (1 << 0) }
    if dpad.down.isPressed { mask |= (1 << 1) }
    if dpad.left.isPressed { mask |= (1 << 2) }
    if dpad.right.isPressed { mask |= (1 << 3) }
    return mask
}

private func buildGamepadMapping(sysButtons: [ButtonInfo], gamepad: GCExtendedGamepad) -> [(GCControllerButtonInput, Int)] {
    var mapping: [(GCControllerButtonInput, Int)] = []

    // Map system buttons to gamepad buttons by position in the array
    // Standard mapping: A->first, B->second, X->third, Y->fourth, L->fifth, R->sixth
    let gcButtons: [GCControllerButtonInput] = [
        gamepad.buttonA,
        gamepad.buttonB,
        gamepad.buttonX,
        gamepad.buttonY,
        gamepad.leftShoulder,
        gamepad.rightShoulder,
    ]

    for (i, sysButton) in sysButtons.enumerated() {
        if i < gcButtons.count {
            mapping.append((gcButtons[i], sysButton.id))
        }
    }

    return mapping
}

private func buildGamepadButtonMask(gamepad: GCExtendedGamepad, mapping: [(GCControllerButtonInput, Int)]) -> Int {
    var mask = 0
    for (gcButton, bitID) in mapping {
        if gcButton.isPressed {
            mask |= (1 << bitID)
        }
    }
    return mask
}

/// Metal view wrapper for SwiftUI
struct MetalEmulatorView: UIViewRepresentable {
    let manager: EmulatorManager
    let size: CGSize

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = manager.fps
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.autoResizeDrawable = true

        // Create renderer and attach to view
        manager.setupRenderer(for: mtkView)

        if let renderer = manager.renderer {
            renderer.viewSize = size
            renderer.onFrameRequest = { [weak manager] in
                manager?.getFrameData()
            }
        }

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        manager.renderer?.viewSize = size
        uiView.drawableSize = CGSize(width: size.width * UIScreen.main.scale,
                                      height: size.height * UIScreen.main.scale)
    }
}

/// Pause menu overlay
struct PauseMenuView: View {
    var onResume: () -> Void
    var onLibrary: () -> Void

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Paused")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(.bottom, 20)

                Button(action: onResume) {
                    Text("Resume")
                        .frame(width: 200)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: onLibrary) {
                    Text("Exit to Library")
                        .frame(width: 200)
                        .padding()
                        .background(Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(40)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(20)
        }
    }
}

/// Manages emulator state and frame loop
class EmulatorManager: ObservableObject {
    private let emulator: EmulatorEngine = EmulatorBridge.createEngine()
    private var audioEngine: AudioEngine?
    private(set) var renderer: MetalRenderer?

    // Emulation runs on dedicated high-priority thread
    private var emulationThread: Thread?
    private var isRunning = false
    private var isPaused = false
    private let emulationLock = NSLock()

    // Cached frame data for fast access from Metal renderer
    private var cachedFrameData: FrameData?
    private let frameBufferLock = NSLock()

    private let saveStateManager = SaveStateManager()

    var fps: Int {
        emulator.fps
    }

    func loadROM(path: String) -> Bool {
        return emulator.loadROM(path: path)
    }

    func start(muted: Bool) {
        // Always setup audio engine (needed for audio-driven timing even when muted)
        audioEngine = AudioEngine()
        do {
            try audioEngine?.start(muted: muted)
        } catch {
            Log.emulator.error("Failed to start audio engine: \(error.localizedDescription)")
        }

        // Start emulation on dedicated thread
        isRunning = true
        isPaused = false
        emulationThread = Thread { [weak self] in
            self?.emulationLoop()
        }
        emulationThread?.qualityOfService = .userInteractive
        emulationThread?.name = "EmulatorThread"
        emulationThread?.start()
    }

    func stop() {
        isRunning = false

        // Wait for emulation thread to finish before releasing
        while emulationThread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.001)
        }
        emulationThread = nil

        audioEngine?.stop()
        audioEngine = nil
        emulator.unload()
    }

    func pause() {
        emulationLock.lock()
        defer { emulationLock.unlock() }
        isPaused = true
        audioEngine?.clearBuffer()
    }

    func resume() {
        emulationLock.lock()
        defer { emulationLock.unlock() }
        isPaused = false
    }

    private func emulationLoop() {
        let targetFPS = fps
        let frameTime = 1.0 / Double(targetFPS)
        var lastFrameTime = CACurrentMediaTime()

        while isRunning {
            autoreleasepool {
                // Check if paused
                emulationLock.lock()
                let paused = isPaused
                emulationLock.unlock()

                if paused {
                    Thread.sleep(forTimeInterval: 0.01)
                    lastFrameTime = CACurrentMediaTime()
                    return
                }

                emulator.runFrame()

                frameBufferLock.lock()
                cachedFrameData = emulator.getFrameBuffer()
                frameBufferLock.unlock()

                if let samples = emulator.getAudioSamples() {
                    audioEngine?.queueSamples(samples)
                }

                // --- Timing ---
                let now = CACurrentMediaTime()
                let elapsed = now - lastFrameTime
                var sleepTime = frameTime - elapsed

                let bufferLevel = audioEngine?.getBufferLevel() ?? AudioEngine.targetBufferLevel
                if bufferLevel < AudioEngine.minBufferLevel {
                    sleepTime *= 0.9
                } else if bufferLevel > AudioEngine.maxBufferLevel {
                    sleepTime *= 1.1
                }

                if sleepTime > 0.001 {
                    Thread.sleep(forTimeInterval: sleepTime)
                }

                lastFrameTime = CACurrentMediaTime()
            }
        }
    }

    func getFrameData() -> FrameData? {
        frameBufferLock.lock()
        let data = cachedFrameData
        frameBufferLock.unlock()
        return data
    }

    func setInput(player: Int, buttons: Int) {
        emulator.setInput(player: player, buttons: buttons)
    }

    func applyCoreOptions(_ options: [String: String]) {
        for (key, value) in options {
            emulator.setOption(key: key, value: value)
        }
    }

    // MARK: - Save State

    func saveResumeState(gameCRC: String) {
        guard emulator.hasSaveStates else { return }
        saveStateManager.setGame(crc: gameCRC)
        guard let data = emulator.serialize() else {
            return
        }
        do {
            try saveStateManager.saveResumeState(data: data)
        } catch {
            Log.storage.error("Failed to save resume state: \(error.localizedDescription)")
        }
    }

    func loadResumeState(gameCRC: String) {
        guard emulator.hasSaveStates else { return }
        saveStateManager.setGame(crc: gameCRC)
        do {
            let data = try saveStateManager.loadResumeState()
            _ = emulator.deserialize(data: data)
        } catch {
            Log.storage.debug("Resume state not loaded: \(error.localizedDescription)")
        }
    }

    func saveSRAM(gameCRC: String) {
        guard emulator.hasSRAM else { return }
        saveStateManager.setGame(crc: gameCRC)
        guard let data = emulator.getSRAM() else { return }
        do {
            try saveStateManager.saveSRAM(data: data)
        } catch {
            Log.storage.error("Failed to save SRAM: \(error.localizedDescription)")
        }
    }

    func loadSRAM(gameCRC: String) {
        guard emulator.hasSRAM else { return }
        saveStateManager.setGame(crc: gameCRC)
        do {
            let data = try saveStateManager.loadSRAM()
            emulator.setSRAM(data: data)
        } catch {
            Log.storage.debug("SRAM not loaded: \(error.localizedDescription)")
        }
    }

    func setupRenderer(for mtkView: MTKView) {
        renderer = MetalRenderer(mtkView: mtkView)
        mtkView.delegate = renderer
    }
}
