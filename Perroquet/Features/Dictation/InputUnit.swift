import AVFoundation
import AudioToolbox
import CoreAudio

/// An input-only HAL audio unit: it captures one device without ever opening the default output device, which an
/// `AVAudioEngine` does and which wakes up, or reconfigures, the speakers or headset.
///
/// The unit stays initialized between recordings; `start` and `pause` only start and stop the hardware I/O.
@MainActor
final class InputUnit {
    /// Reasons the unit cannot capture.
    enum Failure: Error {
        /// The device reports no usable sample rate or channel count.
        case invalidFormat
        /// There is no input device to capture.
        case noInputDevice
        /// The system has no HAL audio unit to create.
        case unitUnavailable
    }

    /// What the unit is set up for: the format of the buffers it hands out and their largest frame count.
    struct Configuration: Equatable {
        let format: AVAudioFormat
        let maxFrames: UInt32
    }

    /// Called on the main actor when the device changes sample rate or stream format.
    var onFormatChange: (() -> Void)?

    private let unit: AudioUnit
    private let context = RenderContext()
    private let device: AudioDeviceID
    private var configured: Configuration?
    private var listener: AudioObjectPropertyListenerBlock?
    private var isDisposed = false

    private static let minimumFrames: UInt32 = 4096
    private static let inputElement: AudioUnitElement = 1
    private static let outputElement: AudioUnitElement = 0
    private static let formatAddresses = [
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain),
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain),
    ]

    /// Creates a unit capturing `device`, or the system default input when nil.
    init(device: AudioDeviceID?) throws {
        guard let device = device ?? InputDevices.defaultInputID() else {
            throw Failure.noInputDevice
        }
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw Failure.unitUnavailable
        }
        var instance: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &instance))
        guard let instance else { throw Failure.unitUnavailable }
        self.unit = instance
        self.device = device
        context.unit = instance
        try setUp()
    }

    isolated deinit {
        dispose()
    }

    /// Whether the device's current format differs from the one the unit is set up for.
    var needsConfigure: Bool {
        guard let wanted = try? deviceConfiguration() else { return true }
        return wanted != configured
    }

    /// Reads the device's current format and, when it differs from the one set up, reconfigures the unit for it.
    /// Returns what the buffers handed to `start`'s handler look like. Call it only while the unit is paused.
    func configure() throws -> Configuration {
        let wanted = try deviceConfiguration()
        if let configured, configured == wanted { return configured }
        if configured != nil {
            try Self.check(AudioUnitUninitialize(unit))
            configured = nil
        }
        var description = wanted.format.streamDescription.pointee
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, Self.inputElement, &description,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
        var frames = wanted.maxFrames
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, Self.outputElement, &frames,
                UInt32(MemoryLayout<UInt32>.size)))
        context.buffer = AVAudioPCMBuffer(pcmFormat: wanted.format, frameCapacity: frames)
        try Self.check(AudioUnitInitialize(unit))
        configured = wanted
        return wanted
    }

    private func deviceConfiguration() throws -> Configuration {
        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(
            AudioUnitGetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, Self.inputElement, &hardware, &size))
        guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0, let format = Self.clientFormat(hardware) else {
            throw Failure.invalidFormat
        }
        let frames = max(Self.minimumFrames, InputDevices.bufferFrameSize(device) ?? 0)
        return Configuration(format: format, maxFrames: frames)
    }

    /// Starts the hardware I/O; `handler` receives each captured buffer, in the format `configure` returned, on the
    /// real-time audio thread. The buffer is reused for the next callback, so `handler` must not keep it.
    func start(handler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        context.handler = handler
        do {
            try Self.check(AudioOutputUnitStart(unit))
        } catch {
            context.handler = nil
            throw error
        }
    }

    /// Stops the hardware I/O, leaving the unit initialized for the next `start`.
    func pause() {
        AudioOutputUnitStop(unit)
        context.handler = nil
    }

    /// Stops and releases the unit; it cannot be used afterwards.
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        removeListener()
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        context.handler = nil
        context.unit = nil
    }

    /// Routes the unit to input only and installs the capture callback, before it is initialized.
    private func setUp() throws {
        var enabled: UInt32 = 1
        var disabled: UInt32 = 0
        let flag = UInt32(MemoryLayout<UInt32>.size)
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, Self.inputElement, &enabled, flag))
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, Self.outputElement, &disabled, flag))
        var device = device
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)))
        var callback = AURenderCallbackStruct(
            inputProc: inputCallback, inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
        try Self.check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
        addListener()
    }

    private func addListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onFormatChange?() }
        }
        listener = block
        for var address in Self.formatAddresses {
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
    }

    private func removeListener() {
        guard let listener else { return }
        for var address in Self.formatAddresses {
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener)
        }
        self.listener = nil
    }

    /// The device's rate and channel count as the non-interleaved Float32 format the unit hands out.
    private static func clientFormat(_ hardware: AudioStreamBasicDescription) -> AVAudioFormat? {
        let channels = AVAudioChannelCount(hardware.mChannelsPerFrame)
        if let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: hardware.mSampleRate, channels: channels, interleaved: false)
        {
            return format
        }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels) else {
            return nil
        }
        return AVAudioFormat(standardFormatWithSampleRate: hardware.mSampleRate, channelLayout: layout)
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

/// State the audio thread reads: the unit to render from, the buffer to render into and the handler to pass it to.
/// `@unchecked Sendable`: the main actor changes it only while the hardware I/O is stopped, the audio thread only
/// reads it.
private final class RenderContext: @unchecked Sendable {
    var unit: AudioUnit?
    var buffer: AVAudioPCMBuffer?
    var handler: ((AVAudioPCMBuffer) -> Void)?

    func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, bus: UInt32,
        frames: UInt32
    ) -> OSStatus {
        guard let unit, let buffer, let handler else { return noErr }
        guard frames <= buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
        buffer.frameLength = frames
        let status = AudioUnitRender(unit, flags, timeStamp, bus, frames, buffer.mutableAudioBufferList)
        if status == noErr { handler(buffer) }
        return status
    }
}

private let inputCallback: AURenderCallback = { refCon, flags, timeStamp, bus, frames, _ in
    Unmanaged<RenderContext>.fromOpaque(refCon).takeUnretainedValue()
        .render(flags: flags, timeStamp: timeStamp, bus: bus, frames: frames)
}
