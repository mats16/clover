@preconcurrency import AVFoundation
import CoreMedia
import os
import Speech

/// オーディオキャプチャコールバックから SpeechAnalyzer が消費する
/// AsyncStream<AnalyzerInput> へのブリッジ。
/// AudioCaptureManager / SystemAudioCaptureManager の onAudioBuffer コールバックから
/// appendBuffer() を呼び出し、SpeechAnalyzer.start(inputSequence:) に stream を渡す。
final class AudioBufferBridge: @unchecked Sendable {
    let stream: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    /// 累積サンプル数（bufferStartTime 計算用）
    private var cumulativeSampleCount: Int64 = 0
    private let sampleRate: Double
    private let lock = OSAllocatedUnfairLock()

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stream = stream
        self.continuation = continuation
    }

    /// オーディオキャプチャコールバックから呼ばれる。スレッドセーフ。
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        let startTime: CMTime = lock.withLock {
            let time = CMTime(value: cumulativeSampleCount, timescale: CMTimeScale(sampleRate))
            cumulativeSampleCount += Int64(buffer.frameLength)
            return time
        }

        let input = AnalyzerInput(buffer: buffer, bufferStartTime: startTime)
        continuation.yield(input)
    }

    /// オーディオ入力の終了を通知する。
    func finish() {
        continuation.finish()
    }
}
