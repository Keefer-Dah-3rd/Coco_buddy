#if DEBUG
import AVFoundation

/// Checks the microphone facts voice input relies on and the silence rule, without opening
/// the mic. Debug builds only:
///
///     Coco.app/Contents/MacOS/Coco --voice-selftest
enum VoiceSelfTest {
    static func run() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print("\(ok ? "PASS" : "FAIL")  \(what)")
            if !ok { failures += 1 }
        }

        // What this Mac reports right now (not pass/fail: it depends on how the Mac is set up).
        let input = MicrophoneCheck.defaultInput()
        let lidClosed = MicrophoneCheck.isLidClosed()
        print("info  default input: \(input.map { "\($0.name) (built-in: \($0.isBuiltIn))" } ?? "none")")
        print("info  lid closed: \(lidClosed)")
        print("info  voice input would \(input?.isBuiltIn == true && lidClosed ? "refuse: lid closed" : "listen")")
        check(input != nil, "a default input device is found")

        // The silence rule, with made-up audio.
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        func buffer(seconds: Double, amplitude: Float) -> AVAudioPCMBuffer {
            let frames = AVAudioFrameCount(48_000 * seconds)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            let samples = buffer.floatChannelData![0]
            for i in 0..<Int(frames) { samples[i] = amplitude * (i.isMultiple(of: 2) ? 1 : -1) }
            return buffer
        }
        func meter(_ buffers: [AVAudioPCMBuffer]) -> LevelMeter.Reading {
            let meter = LevelMeter()
            buffers.forEach(meter.record)
            return meter.reading
        }

        let zeros = meter([buffer(seconds: 3, amplitude: 0), buffer(seconds: 3, amplitude: 0)])
        check(abs(zeros.seconds - 6) < 0.01, "the meter counts the audio it was given (\(zeros.seconds) s)")
        check(LevelMeter.isSilent(zeros, listenedFor: 6), "six seconds of zeros is silence (a switched-off mic)")

        // A working MacBook mic's own hiss in a quiet room sits around −70 dBFS.
        let hiss = meter([buffer(seconds: 6, amplitude: 0.0003)])
        check(!LevelMeter.isSilent(hiss, listenedFor: 6), "a quiet room is not silence (peak \(hiss.peak))")
        let speech = meter([buffer(seconds: 2, amplitude: 0), buffer(seconds: 1, amplitude: 0.2)])
        check(!LevelMeter.isSilent(speech, listenedFor: 3), "one loud second among zeros is not silence")
        check(!LevelMeter.isSilent(zeros, listenedFor: 0.8), "a tap-and-stop under 1.5 s is too short to judge")
        check(LevelMeter.isSilent(LevelMeter.Reading(), listenedFor: 6), "no audio at all after six seconds counts as silence")

        // Every problem has a line for Coco and, where one exists, a settings page.
        let problems: [VoiceInput.Problem] = [.speechPermission, .microphonePermission, .speechUnavailable,
                                              .noMicrophone, .lidClosed, .silentMicrophone]
        check(problems.allSatisfy { !BuddyVoice.cantHear($0).isEmpty }, "Coco has a line for every problem")

        // Today's "Make a little plan" never does nothing: without a chat set up it opens the form.
        let model = AppModel(preview: true)
        model.panelTab = .today
        check(!model.assistant.isReady, "the preview model has no chat set up")
        model.makeLittlePlan()
        check(model.taskForm != nil && model.panelTab == .today, "“Make a little plan” without chat opens the new-task form")

        print(failures == 0 ? "voice selftest: all passed" : "voice selftest: \(failures) FAILED")
    }
}
#endif
