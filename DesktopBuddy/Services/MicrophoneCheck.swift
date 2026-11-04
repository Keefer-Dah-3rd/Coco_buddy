import Accelerate
import AVFoundation
import CoreAudio
import IOKit
import os

/// Facts about the Mac's microphone that explain a recording with nothing in it.
///
/// Voice input reads these before it opens the mic, so Coco can say *why* she can't hear
/// instead of listening to six seconds of silence and saying "I didn't catch that".
nonisolated enum MicrophoneCheck {
    struct Input: Equatable {
        let name: String
        /// The Mac's own microphone — in a laptop, the one in the lid.
        let isBuiltIn: Bool
    }

    /// The input macOS records from by default, which is the one AVAudioEngine's input node uses.
    static func defaultInput() -> Input? {
        guard let id = uint32(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice),
              id != kAudioObjectUnknown else { return nil }
        let transport = uint32(of: id, kAudioDevicePropertyTransportType)
        return Input(name: name(of: id) ?? "the microphone", isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    /// True while a laptop's lid is shut (for example, docked to an external display).
    ///
    /// Every Mac this app runs on — Apple silicon, or Intel with the T2 chip — disconnects the
    /// built-in microphone in hardware while the lid is closed, so it records pure silence.
    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}

/// The loudest sample and the amount of audio heard in one listening session.
///
/// Written from the audio tap's thread, read on the main actor when listening ends.
nonisolated final class LevelMeter: Sendable {
    struct Reading {
        var peak: Float = 0
        var seconds: Double = 0
    }

    /// Below this peak (about −80 dBFS) nothing came through at all. A working microphone in a
    /// quiet room still picks up its own hiss well above it; a switched-off one sends zeros.
    static let silenceFloor: Float = 0.0001

    private let state = OSAllocatedUnfairLock(initialState: Reading())

    func record(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var loudest: Float = 0
        vDSP_maxmgv(samples, 1, &loudest, vDSP_Length(buffer.frameLength))
        let peak = loudest
        let seconds = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        state.withLock {
            $0.peak = max($0.peak, peak)
            $0.seconds += seconds
        }
    }

    var reading: Reading { state.withLock { $0 } }

    /// Long enough to judge, and nothing but silence (or no audio at all).
    static func isSilent(_ reading: Reading, listenedFor seconds: TimeInterval) -> Bool {
        seconds >= 1.5 && reading.peak < silenceFloor
    }
}
