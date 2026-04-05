@preconcurrency import AVFoundation

enum AudioCaptureError: Error, LocalizedError {
    case invalidHardwareFormat
    case converterCreationFailed
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidHardwareFormat:
            L10n.invalidHardwareFormat
        case .converterCreationFailed:
            L10n.converterCreationFailed
        case .microphonePermissionDenied:
            L10n.microphoneDenied
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

    /// マイクキャプチャを開始する。
    func startCapture(targetFormat: AVAudioFormat) throws {
        self.captureFormat = targetFormat
        let inputNode = engine.inputNode
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
}
