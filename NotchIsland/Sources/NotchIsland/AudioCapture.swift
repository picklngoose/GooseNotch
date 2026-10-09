import AVFoundation
import Speech

/// Records microphone audio to an .m4a file and feeds the same buffers to
/// Apple's speech recognizer for a live transcript.
///
/// Deliberately not main-actor isolated: AVAudioEngine and the Speech framework call
/// back on their own threads, and closures created here must not inherit main-actor isolation.
final class AudioCapture: @unchecked Sendable {
    struct CaptureError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var onLevel: (@Sendable (Float) -> Void)?
    var onTranscript: (@Sendable (String) -> Void)?
    private(set) var isTranscribing = false

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var committed = ""
    private var current = ""
    private var generation = 0
    private var running = false

    func start(url: URL, transcribe: Bool) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError(message: "No microphone input is available.")
        }
        guard format.channelCount <= 2 else {
            throw CaptureError(message: "Unsupported microphone channel layout.")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 96_000
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings)

        lock.lock()
        file = newFile
        committed = ""
        current = ""
        running = true
        lock.unlock()

        if transcribe,
           let rec = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
           rec.isAvailable {
            recognizer = rec
            isTranscribing = true
            beginSegment()
        } else {
            recognizer = nil
            isTranscribing = false
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.lock()
            running = false
            file = nil
            let req = request
            request = nil
            lock.unlock()
            req?.endAudio()
            task?.cancel()
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        running = false
        file = nil               // releases and finalizes the m4a
        let req = request
        request = nil
        lock.unlock()

        req?.endAudio()          // lets the recognizer deliver its final result
    }

    // MARK: Audio thread

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        try? file?.write(from: buffer)
        request?.append(buffer)
        lock.unlock()

        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 0.00001))
        onLevel?(max(0, min(1, (db + 50) / 50)))
    }

    // MARK: Speech

    private func beginSegment() {
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        lock.lock()
        generation += 1
        let gen = generation
        request = req
        lock.unlock()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            self?.handle(result: result, error: error, generation: gen)
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation gen: Int) {
        lock.lock()
        guard gen == generation else {
            lock.unlock()
            return
        }
        var emit: String?
        if let result {
            current = Self.join(committed, result.bestTranscription.formattedString)
            emit = current
        }
        let isFinal = result?.isFinal ?? false
        let ended = isFinal || error != nil
        if ended { committed = current }
        let keepGoing = running
        lock.unlock()

        if let emit { onTranscript?(emit) }

        // Recognition segments end after silence or a time limit; roll into a new one
        // so the transcript keeps going for as long as the recording does.
        if ended, keepGoing {
            let delay: TimeInterval = isFinal ? 0.05 : 0.5
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let ok = self.running && self.generation == gen
                self.lock.unlock()
                if ok { self.beginSegment() }
            }
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}
