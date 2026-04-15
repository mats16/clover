import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio

enum AudioCaptureError: Error, LocalizedError {
    case invalidHardwareFormat
    case converterCreationFailed
    case microphonePermissionDenied
    case microphoneDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidHardwareFormat:
            L10n.invalidHardwareFormat
        case .converterCreationFailed:
            L10n.converterCreationFailed
        case .microphonePermissionDenied:
            L10n.microphoneDenied
        case .microphoneDeviceUnavailable:
            L10n.microphoneUnavailable
        }
    }
}

/// AVAudioEngine を使用してマイクからオーディオをキャプチャし、
/// 指定されたターゲットフォーマットに変換して AVAudioPCMBuffer で出力する。
final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?

    /// 変換済み AVAudioPCMBuffer のコールバック（オーディオスレッドから呼ばれる）
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// マイクのパーミッションを確認・要求する。
    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// 利用可能なマイク入力デバイス一覧を返す。
    static func availableInputDevices() -> [MicrophoneDevice] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var propertySize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        ) == noErr else {
            return []
        }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs
            .filter(Self.hasInputStreams)
            .compactMap { deviceID in
                guard let name = Self.deviceName(for: deviceID) else { return nil }
                return MicrophoneDevice(id: deviceID, name: name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// 現在のデフォルト入力デバイス ID を返す。
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        ) == noErr,
            deviceID != 0
        else {
            return nil
        }

        return deviceID
    }

    /// マイクキャプチャを開始する。
    func startCapture(targetFormat: AVAudioFormat, selectedDeviceID: AudioDeviceID? = nil) throws {
        self.captureFormat = targetFormat
        let inputNode = engine.inputNode

        if let selectedDeviceID {
            try Self.configureInputDevice(selectedDeviceID, for: inputNode)
        }

        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidHardwareFormat
        }

        guard let conv = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        conv.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        self.converter = conv

        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) {
            [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// キャプチャを停止する。
    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        captureFormat = nil
    }

    private func processAudioBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat = captureFormat else { return }
        guard let outputBuffer = AudioConverter.convert(inputBuffer, to: targetFormat, using: converter) else { return }
        onAudioBuffer?(outputBuffer)
    }

    private static func configureInputDevice(_ deviceID: AudioDeviceID, for inputNode: AVAudioInputNode) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.microphoneDeviceUnavailable
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioCaptureError.microphoneDeviceUnavailable
        }
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0

        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize) == noErr && propertySize > 0
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = globalAddress(kAudioObjectPropertyName)
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        var name: Unmanaged<CFString>?

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &name
        ) == noErr,
            let name
        else {
            return nil
        }

        return name.takeUnretainedValue() as String
    }
}
