import AVFoundation
import AudioToolbox
import MediaToolbox
import Observation

/// Owns one allocation-free Rust filter reader and its preallocated PCM channel pointers.
private final class AudioTapContext {
    let stage: UnsafeMutableRawPointer
    let counter: UnsafeRawPointer?
    let planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    var supported = false
    var interleaved = false
    var channels = 0

    init?() {
        guard let stage = sonora_audio_stage_create() else { return nil }
        self.stage = stage
        counter = sonora_audio_stage_counter(stage)
        planes = .allocate(capacity: 8)
        planes.initialize(repeating: nil, count: 8)
    }

    deinit {
        sonora_audio_stage_destroy(stage)
        planes.deinitialize(count: 8)
        planes.deallocate()
    }
}

private func tapContext(_ tap: MTAudioProcessingTap) -> AudioTapContext {
    Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private func initializeAudioTap(_ tap: MTAudioProcessingTap, _ info: UnsafeMutableRawPointer?,
                                _ storage: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    guard let info else { return }
    let context = Unmanaged<AudioTapContext>.fromOpaque(info).takeUnretainedValue()
    storage.pointee = Unmanaged.passRetained(context).toOpaque()
}

private func finalizeAudioTap(_ tap: MTAudioProcessingTap) {
    Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

/// Format preparation and discontinuity resets happen before samples enter the shared DSP.
private func prepareAudioTap(_ tap: MTAudioProcessingTap, _ maximum: CMItemCount,
                             _ description: UnsafePointer<AudioStreamBasicDescription>) {
    let context = tapContext(tap)
    let format = description.pointee
    context.supported = false
    guard format.mFormatID == kAudioFormatLinearPCM,
          format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
          format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
          format.mBitsPerChannel == 32, (1...8).contains(format.mChannelsPerFrame),
          format.mSampleRate.isFinite, (8_000...384_000).contains(format.mSampleRate) else { return }
    context.channels = Int(format.mChannelsPerFrame)
    context.interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    context.supported = sonora_audio_stage_format(context.stage, UInt32(format.mSampleRate.rounded()), format.mChannelsPerFrame) == 0
}

/// The render callback performs no allocations, locks, file access, networking or Swift tasks.
private func processAudioTap(_ tap: MTAudioProcessingTap, _ requested: CMItemCount,
                             _ flags: MTAudioProcessingTapFlags, _ buffers: UnsafeMutablePointer<AudioBufferList>,
                             _ frames: UnsafeMutablePointer<CMItemCount>, _ outputFlags: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, requested, buffers, outputFlags, nil, frames)
    guard status == noErr else { frames.pointee = 0; return }
    let context = tapContext(tap)
    guard context.supported, frames.pointee > 0, frames.pointee <= 65_536 else { return }
    let list = UnsafeMutableAudioBufferListPointer(buffers)
    let count = context.interleaved ? 1 : context.channels
    guard list.count == count else { return }
    for index in 0..<count {
        let buffer = list[index]
        let channels = context.interleaved ? context.channels : 1
        guard Int(buffer.mNumberChannels) == channels,
              Int(buffer.mDataByteSize) >= frames.pointee * channels * MemoryLayout<Float>.size,
              let data = buffer.mData else { return }
        context.planes[index] = data.assumingMemoryBound(to: Float.self)
    }
    if outputFlags.pointee & kMTAudioProcessingTapFlag_StartOfStream != 0 {
        sonora_audio_stage_reset(context.stage)
    }
    _ = sonora_audio_stage_process(context.stage, context.planes, frames.pointee, context.interleaved)
}

/// Attaches the desktop filters to native local and progressive AAC playback and owns control tasks.
@MainActor @Observable
final class NativeAudioEffects {
    private var configurationError: String?
    private var attachmentError: String?
    var error: String? { configurationError ?? attachmentError }
    private(set) var preampDB: Double = 0
    private(set) var isAttached = false
    private(set) var isPreparing = false
    @ObservationIgnored private var context: AudioTapContext?
    @ObservationIgnored private var item: AVPlayerItem?
    @ObservationIgnored private var attachTask: Task<Void, Never>?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0

    var processedFrames: UInt64 {
        guard let context else { return 0 }
        return sonora_audio_counter_frames(context.counter)
    }

    func configure(settings: SettingsStore, normalizationDB: Double) {
        configurationTask?.cancel()
        revision &+= 1
        let revision = revision
        let request: [String: Any] = [
            "operation": "equalizer_configure", "revision": revision,
            "enabled": settings.equalizerEnabled, "preset": settings.equalizerPreset.coreID,
            "auto_preamp": settings.autoPreamp, "preamp_db": settings.preampDB,
            "bass_db": settings.bassDB, "treble_db": settings.trebleDB,
            "normalization_db": normalizationDB
        ]
        configurationTask = Task { [weak self] in
            do {
                let result = try await NativeProvider.configureEqualizer(request)
                guard let self, self.revision == revision else { return }
                self.preampDB = result.preamp_db
                self.configurationError = nil
            } catch is CancellationError {
            } catch {
                guard let self, self.revision == revision else { return }
                self.configurationError = String(localized: "ios-audio-effects-error")
            }
        }
    }

    /// Asynchronous asset inspection preserves the UI thread and ignores replaced player items.
    func attach(to item: AVPlayerItem, completion: @escaping () -> Void) {
        attachTask?.cancel()
        self.item = item
        context = nil
        isAttached = false
        attachmentError = nil
        isPreparing = true
        attachTask = Task { [weak self] in
            do {
                await self?.configurationTask?.value
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard !Task.isCancelled, let self, self.item === item,
                      let track = tracks.first, let context = AudioTapContext() else {
                    throw ProviderError.unavailable
                }
                var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
                    clientInfo: Unmanaged.passUnretained(context).toOpaque(), init: initializeAudioTap,
                    finalize: finalizeAudioTap, prepare: prepareAudioTap, unprepare: nil, process: processAudioTap)
                var tap: MTAudioProcessingTap?
                let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                    kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
                guard status == noErr, let tap else { throw ProviderError.unavailable }
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.audioTapProcessor = tap
                let mix = AVMutableAudioMix()
                mix.inputParameters = [parameters]
                self.context = context
                item.audioMix = mix
                self.isAttached = true
                self.isPreparing = false
                completion()
            } catch is CancellationError {
            } catch {
                guard let self, self.item === item else { return }
                self.attachmentError = String(localized: "ios-audio-effects-error")
                self.isPreparing = false
                completion()
            }
        }
    }

    func detach() {
        attachTask?.cancel()
        attachTask = nil
        item = nil
        context = nil
        isAttached = false
        isPreparing = false
        attachmentError = nil
    }

    /// A tap which passes unsupported PCM through must not be presented as working DSP.
    func reportUnprocessedAudio() {
        guard isAttached, processedFrames == 0 else { return }
        isAttached = false
        attachmentError = String(localized: "ios-audio-effects-error")
    }
}
