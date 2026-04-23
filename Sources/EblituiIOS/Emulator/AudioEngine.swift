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

    // Back-pressure target: producer parks when this many sample frames
    // are queued into AVAudioEngine and not yet played. 2400 frames at
    // 48kHz = 50ms of queued audio; plus AVAudioPlayerNode's internal
    // buffer (~50ms) plus the session context buffer (~50ms) puts
    // end-to-end latency around 150ms. Smaller values tighten latency at
    // the cost of more audible glitches on transient hitches; larger
    // values are safer but less responsive.
    static let maxBufferLevel = 2400

    // In-flight sample frame tracking via completion handlers.
    private var inFlightFrames: Int = 0
    private let levelLock = NSLock()
    // Signaled from the scheduleBuffer completion handler when
    // inFlightFrames transitions from >= maxBufferLevel to below it,
    // and from clearBuffer() / stop() to unblock a parked producer.
    private let backPressureSemaphore = DispatchSemaphore(value: 0)

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

    /// Stop the audio engine. Signals any parked producer so the
    /// emulation thread can exit its `queueSamples` call.
    func stop() {
        // Pause first so the node is already silent by the time we
        // discard its scheduled buffers — `stop()` otherwise cuts audio
        // mid-sample and produces an audible click on app quit.
        playerNode?.pause()
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil

        levelLock.lock()
        inFlightFrames = 0
        levelLock.unlock()
        backPressureSemaphore.signal()
    }

    /// Queue audio samples for playback. Blocks when the in-flight frame
    /// count is at or above `maxBufferLevel`, providing back-pressure
    /// that paces the caller to the audio hardware's drain rate — the
    /// completion handler signals the semaphore when enough audio has
    /// played to free up space.
    ///
    /// Converts directly from bridge data (little-endian int16
    /// interleaved stereo) to AVAudioPCMBuffer (float32 non-interleaved)
    /// and schedules immediately.
    func queueSamples(_ data: Data) {
        guard data.count >= 4,
              let player = playerNode,
              let format = audioFormat else { return }

        // Back-pressure: park until in-flight count drops below the cap.
        // `clearBuffer` and `stop` also signal the semaphore, so a user
        // pause or shutdown unblocks a parked producer.
        levelLock.lock()
        while inFlightFrames >= Self.maxBufferLevel {
            levelLock.unlock()
            backPressureSemaphore.wait()
            levelLock.lock()
        }
        levelLock.unlock()

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
            let wasAtCap = self.inFlightFrames >= Self.maxBufferLevel
            self.inFlightFrames -= frameCount
            let nowUnderCap = self.inFlightFrames < Self.maxBufferLevel
            self.levelLock.unlock()

            // Signal only on the at-cap -> under-cap transition to avoid
            // a semaphore syscall on every buffer completion.
            if wasAtCap && nowUnderCap {
                self.backPressureSemaphore.signal()
            }
        }
    }

    /// Pause audio playback without discarding queued buffers. On
    /// `resumePlayback` the already-scheduled audio continues from where
    /// it left off, producing no audible seam. Use this for user-initiated
    /// pause (pause menu, app backgrounding). Does NOT signal the
    /// back-pressure semaphore — the producer naturally unblocks when
    /// playback resumes and buffers drain again.
    func pausePlayback() {
        playerNode?.pause()
    }

    /// Resume playback after `pausePlayback`.
    func resumePlayback() {
        playerNode?.play()
    }

    /// Discard all queued audio and reset state. Causes an abrupt cut in
    /// output (a click/pop); use only when stale audio must be flushed
    /// (e.g. rewind, save-state load). Signals any parked producer.
    func clearBuffer() {
        levelLock.lock()
        inFlightFrames = 0
        levelLock.unlock()

        playerNode?.stop()
        playerNode?.play()

        backPressureSemaphore.signal()
    }

    /// Set the audio volume (0.0 = muted, 1.0 = full volume)
    func setVolume(_ volume: Float) {
        audioEngine?.mainMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }
}

enum AudioError: Error {
    case formatCreationFailed
}
