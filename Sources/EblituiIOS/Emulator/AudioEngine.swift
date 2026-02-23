import Foundation
import AVFoundation

/// Audio playback engine using AVAudioEngine with scheduled buffers
class AudioEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    // Audio format from SystemInfo
    private let sampleRate: Double
    static let channelCount: AVAudioChannelCount = 2

    // Buffer level thresholds (in stereo sample frames)
    static let targetBufferLevel = 3200   // ~67ms target at 48kHz (4 frames at 60fps)
    static let minBufferLevel = 2400      // ~50ms - speed up below this
    static let maxBufferLevel = 4800      // ~100ms - slow down above this

    // In-flight sample frame tracking via completion handlers
    private var inFlightFrames: Int = 0
    private let levelLock = NSLock()

    var isRunning: Bool {
        audioEngine?.isRunning ?? false
    }

    init() {
        self.sampleRate = Double(EmulatorBridge.systemInfo.sampleRate)
    }

    /// Start the audio engine
    func start(muted: Bool = false) throws {
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(sampleRate)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        // Create format: stereo float32 at system sample rate
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: Self.channelCount,
            interleaved: false
        ) else {
            throw AudioError.formatCreationFailed
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Set volume before starting to prevent pop when muted
        engine.mainMixerNode.outputVolume = muted ? 0.0 : 1.0

        try engine.start()
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.audioFormat = format
    }

    /// Stop the audio engine
    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
    }

    /// Queue audio samples for playback
    /// Converts directly from bridge data (little-endian int16 interleaved stereo)
    /// to AVAudioPCMBuffer (float32 non-interleaved) and schedules immediately.
    func queueSamples(_ data: Data) {
        guard data.count >= 4,
              let player = playerNode,
              let format = audioFormat else { return }

        // 2 bytes per sample, 2 channels per frame
        let frameCount = data.count / 4

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            return
        }

        // Convert int16 interleaved to float32 non-interleaved
        let scale: Float = 1.0 / 32768.0
        data.withUnsafeBytes { ptr in
            guard let basePtr = ptr.baseAddress else { return }
            let int16Ptr = basePtr.assumingMemoryBound(to: Int16.self)
            for i in 0..<frameCount {
                leftChannel[i] = Float(int16Ptr[i * 2]) * scale
                rightChannel[i] = Float(int16Ptr[i * 2 + 1]) * scale
            }
        }

        levelLock.lock()
        inFlightFrames += frameCount
        levelLock.unlock()

        player.scheduleBuffer(buffer) { [weak self] in
            guard let self = self else { return }
            self.levelLock.lock()
            self.inFlightFrames -= frameCount
            self.levelLock.unlock()
        }
    }

    /// Clear the audio buffer
    func clearBuffer() {
        levelLock.lock()
        inFlightFrames = 0
        levelLock.unlock()

        playerNode?.stop()
        playerNode?.play()
    }

    /// Get the current buffer level in stereo sample frames
    func getBufferLevel() -> Int {
        levelLock.lock()
        let level = inFlightFrames
        levelLock.unlock()
        return level
    }

    /// Set the audio volume (0.0 = muted, 1.0 = full volume)
    func setVolume(_ volume: Float) {
        audioEngine?.mainMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }
}

enum AudioError: Error {
    case formatCreationFailed
}
