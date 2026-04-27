import Foundation
import AVFoundation

/// Audio playback engine using AVAudioEngine with scheduled buffers.
///
/// Pacing is driven by consumer drain: each `scheduleBuffer` completion
/// handler reports the number of frames the audio device consumed.
/// Those frame counts accumulate in `drainedFrames`, and once per
/// frame's worth (`samplesPerFrame`) the producer is signalled via
/// `waitForDemand`. The emulation thread parks on that signal between
/// frames so the audio device's drain rate is the loop's clock.
///
/// Empty input to `queueSamples` is replaced with a precomputed silent
/// buffer so the demand signal keeps firing during cold-start frames
/// where the core has not yet produced audio.
class AudioEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    // Audio format from SystemInfo (requested rate; actual rate is read
    // from the connected format after start() and used for pacing math).
    private let requestedSampleRate: Double
    private let fps: Int
    static let channelCount: AVAudioChannelCount = 2

    // Producer-side cap on how many frames may be queued ahead of the
    // audio device. Sized to ~50ms at 48kHz; smaller values tighten
    // latency at the cost of more audible glitches on transient
    // hitches, larger values are safer but less responsive. Used to
    // derive `maxPendingDemand` from `samplesPerFrame`.
    static let maxBufferLevel = 2400

    // Initial demand the producer is allowed to consume before the
    // first scheduleBuffer completion fires. AVAudioPlayerNode buffers
    // ~50ms internally before its first completion lands; at 60Hz that
    // is roughly three frames, so four kickstart frames keeps the
    // producer fed across the cold-start window.
    static let kickstartFrames = 4

    // Demand-signal pacing state. `demandCondition` serves as both the
    // mutex and the condition variable for `pendingDemand`.
    private let demandCondition = NSCondition()
    private var samplesPerFrame: Int = 0
    private var drainedFrames: Int = 0
    private var pendingDemand: Int = 0
    private var maxPendingDemand: Int = 0
    private var shutdown: Bool = false

    // Reused across every empty-input frame. AVAudioPlayerNode retains
    // the buffer until completion fires, and the buffer is read-only
    // after construction, so a single shared instance is safe.
    private var silentBuffer: AVAudioPCMBuffer?

    var isRunning: Bool {
        audioEngine?.isRunning ?? false
    }

    init(fps: Int) {
        self.fps = fps
        self.requestedSampleRate = Double(EmulatorBridge.systemInfo.sampleRate)
    }

    /// Start the audio engine.
    ///
    /// `samplesPerFrame` and `maxPendingDemand` are computed from the
    /// actual hardware sample rate after the engine starts, not the
    /// requested rate, because `setPreferredSampleRate` is a request
    /// the hardware may decline. Using the actual rate keeps the
    /// drain accumulator aligned with real-time playback.
    ///
    /// TODO: handle AVAudioSession interruptions (phone call, Siri,
    /// route change). When interrupted, scheduleBuffer completions
    /// stop firing and a producer parked in waitForDemand will stall
    /// indefinitely. Same latent issue existed with the prior
    /// semaphore design and is out of scope for this change.
    func start(muted: Bool = false) throws {
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(requestedSampleRate)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        // Create format: stereo float32 at requested sample rate.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: requestedSampleRate,
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

        // Compute pacing math from the actual rate the engine settled
        // on. Reading mainMixerNode's output format reflects what the
        // hardware accepted.
        let actualRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let perFrame = max(1, Int((actualRate / Double(fps)).rounded()))

        demandCondition.lock()
        samplesPerFrame = perFrame
        maxPendingDemand = max(1, Self.maxBufferLevel / perFrame + 1)
        pendingDemand = Self.kickstartFrames
        drainedFrames = 0
        shutdown = false
        demandCondition.unlock()

        // Build the silent buffer once. PCM buffers from this initializer
        // are zero-filled, so no explicit memset is required.
        if let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(perFrame)) {
            silent.frameLength = AVAudioFrameCount(perFrame)
            silentBuffer = silent
        }
    }

    /// Stop the audio engine. Wakes any producer parked in
    /// `waitForDemand` so the emulation thread can observe shutdown
    /// and exit.
    func stop() {
        // Wake the producer first so it observes shutdown rather than
        // racing into a queueSamples call against a torn-down player.
        demandCondition.lock()
        shutdown = true
        demandCondition.broadcast()
        demandCondition.unlock()

        // Pause first so the node is already silent by the time we
        // discard its scheduled buffers - stop() otherwise cuts audio
        // mid-sample and produces an audible click on app quit.
        playerNode?.pause()
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        silentBuffer = nil
    }

    /// Park the producer until the audio device has drained enough
    /// bytes to request another frame, or until `stop` is called.
    /// Returns true when the caller should run the next frame, false
    /// when the engine is shutting down and the producer should exit.
    func waitForDemand() -> Bool {
        demandCondition.lock()
        while !shutdown && pendingDemand == 0 {
            demandCondition.wait()
        }
        if shutdown {
            demandCondition.unlock()
            return false
        }
        pendingDemand -= 1
        demandCondition.unlock()
        return true
    }

    /// Queue audio samples for playback. `nil` or empty input is
    /// replaced with one frame of silence so the consumer always has
    /// bytes to drain - without this a cold-start frame that produced
    /// no audio would leave demand stuck and deadlock the producer.
    /// Short non-empty input is passed through unchanged; only
    /// zero-length / nil input is padded.
    ///
    /// Converts directly from bridge data (little-endian int16
    /// interleaved stereo) to AVAudioPCMBuffer (float32 non-interleaved)
    /// and schedules immediately.
    func queueSamples(_ data: Data?) {
        guard let player = playerNode, let format = audioFormat else { return }

        // Empty / nil path: schedule the precomputed silent buffer so
        // its completion handler still fires and drives the demand
        // accumulator.
        guard let data, data.count >= 4 else {
            if let silent = silentBuffer {
                let frames = Int(silent.frameLength)
                player.scheduleBuffer(silent) { [weak self] in
                    self?.handleDrain(frames: frames)
                }
            }
            return
        }

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

        player.scheduleBuffer(buffer) { [weak self] in
            self?.handleDrain(frames: frameCount)
        }
    }

    /// Invoked by every scheduled buffer's completion handler with the
    /// number of frames the audio device consumed. Accumulates a
    /// per-frame counter and releases producer demand once per
    /// `samplesPerFrame`, capped at `maxPendingDemand` so a bursty
    /// consumer (e.g. AVAudio's first batch of completions) cannot
    /// enqueue unbounded catch-up work.
    private func handleDrain(frames: Int) {
        demandCondition.lock()
        drainedFrames += frames
        while drainedFrames >= samplesPerFrame {
            drainedFrames -= samplesPerFrame
            if pendingDemand < maxPendingDemand {
                pendingDemand += 1
            }
        }
        if pendingDemand > 0 {
            demandCondition.broadcast()
        }
        demandCondition.unlock()
    }

    /// Pause audio playback without discarding queued buffers. On
    /// `resumePlayback` the already-scheduled audio continues from
    /// where it left off, producing no audible seam. While paused, no
    /// completion handlers fire and `pendingDemand` does not advance;
    /// the producer parks in `waitForDemand` (or hits the emulation
    /// loop's pause check) and resumes naturally when buffers start
    /// completing again. Use this for user-initiated pause (pause menu,
    /// app backgrounding).
    func pausePlayback() {
        playerNode?.pause()
    }

    /// Resume playback after `pausePlayback`.
    func resumePlayback() {
        playerNode?.play()
    }

    /// Discard all queued audio and reset demand state. Causes an
    /// abrupt cut in output (a click/pop); use only when stale audio
    /// must be flushed (e.g. rewind, save-state load). Re-primes
    /// kickstart demand so the producer can keep running once the
    /// player resumes.
    func clearBuffer() {
        demandCondition.lock()
        drainedFrames = 0
        pendingDemand = Self.kickstartFrames
        demandCondition.broadcast()
        demandCondition.unlock()

        playerNode?.stop()
        playerNode?.play()
    }

    /// Set the audio volume (0.0 = muted, 1.0 = full volume)
    func setVolume(_ volume: Float) {
        audioEngine?.mainMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }
}

enum AudioError: Error {
    case formatCreationFailed
}
