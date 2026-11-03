import AVFoundation
import ScreenCaptureKit

// All sample writes run on the same serial queue. Files are closed after that queue drains.
// Configuration is set before startCapture; mutable file state is confined to queue.
final class AudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Transcripted.audio")
    let folder: URL
    var origin = CMTime.zero
    private var files: [SCStreamOutputType: AVAudioFile] = [:]
    private var failure: Error?
    var onFailure: ((Error) -> Void)?

    init(folder: URL) { self.folder = folder }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onFailure?(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard failure == nil, type == .audio || type == .microphone,
              sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              let description = sampleBuffer.formatDescription,
              let format = AVAudioFormat(cmAudioFormatDescription: description) as AVAudioFormat? else { return }
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        guard status == noErr else { report(AppFailure("Could not read captured audio (\(status)).")); return }
        do {
            let file: AVAudioFile
            if let existing = files[type] { file = existing }
            else {
                file = try AVAudioFile(forWriting: folder.appendingPathComponent(type == .audio ? "system.caf" : "microphone.caf"), settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                files[type] = file
            }
            // Preserve shared timing, including silence before a participant starts speaking.
            let relative = CMTimeSubtract(sampleBuffer.presentationTimeStamp, origin).seconds
            guard relative.isFinite else { throw AppFailure("Audio capture returned an invalid timestamp.") }
            let target = AVAudioFramePosition(max(0, relative) * format.sampleRate)
            var gap = target - file.length
            if gap > AVAudioFramePosition(format.sampleRate * 60 * 60 * 24) { throw AppFailure("Audio capture clock is out of range.") }
            if gap > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) {
                silence.frameLength = silence.frameCapacity
                for item in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                    if let data = item.mData { memset(data, 0, Int(item.mDataByteSize)) }
                }
                while gap > 0 {
                    silence.frameLength = AVAudioFrameCount(min(gap, 8192))
                    try file.write(from: silence)
                    gap -= AVAudioFramePosition(silence.frameLength)
                }
            }
            try file.write(from: buffer)
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        failure = error
        DispatchQueue.main.async { self.onFailure?(error) }
    }

    func close() async -> Error? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.files.removeAll()
                continuation.resume(returning: self.failure)
            }
        }
    }
}

@MainActor
final class Recorder: NSObject, AVAudioRecorderDelegate {
    private var microphone: AVAudioRecorder?
    private var stream: SCStream?
    private var sink: AudioSink?
    var onFailure: ((Error) -> Void)?

    func start(folder: URL, systemAudio: Bool) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw AppFailure("Microphone access is required. Enable Transcripted in System Settings → Privacy & Security → Microphone.")
        }
        if !systemAudio {
            let recorder = try AVAudioRecorder(url: folder.appendingPathComponent("microphone.caf"), settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            recorder.delegate = self
            guard recorder.record() else { throw AppFailure("The microphone could not start recording.") }
            microphone = recorder
            return
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw AppFailure("No display is available for system audio capture. Select microphone-only mode.") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        let output = AudioSink(folder: folder)
        output.onFailure = onFailure
        let capture = SCStream(filter: filter, configuration: configuration, delegate: output)
        try capture.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try capture.addStreamOutput(output, type: .microphone, sampleHandlerQueue: output.queue)
        output.origin = CMClockGetTime(CMClockGetHostTimeClock())
        do { try await capture.startCapture() }
        catch { _ = await output.close(); throw error }
        sink = output
        stream = capture
    }

    func stop() async -> Error? {
        microphone?.stop()
        microphone = nil
        var failure: Error?
        if let stream {
            do { try await stream.stopCapture() } catch { failure = error }
        }
        stream = nil
        if let sink, let error = await sink.close() { failure = error }
        sink = nil
        return failure
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.onFailure?(error ?? AppFailure("Microphone recording failed.")) }
    }
}
