import AVFoundation
import CoreAudio
import os

/// What the Mac is playing, heard along with the microphone while you dictate, when HEAR THE MAC'S SOUND TOO is on:
/// the other side of a call, or a video. It comes from a Core Audio "tap" on everything the Mac plays except Notch
/// itself, so Notch's own sounds are never written down. The tap only listens: the sound plays on as loud as it was.
///
/// A tap is read the way a microphone is, through a device: here a private one that holds only the tap and that no
/// other app can see. Core Audio hands over each new piece of sound, and the piece waits in a `Backlog` until the
/// microphone's next buffer takes it.
enum MacSound {
    private static let queue = DispatchQueue(label: "notch.macsound", qos: .userInteractive)   // making and taking down the tap can block for a moment, so it happens here, in order
    // Only touched on `queue`.
    private static var wanted = false                                 // a dictation wants the Mac's sound
    private static var tap = AudioObjectID(kAudioObjectUnknown)       // the tap on everything the Mac plays
    private static var device = AudioObjectID(kAudioObjectUnknown)    // the private device that holds it
    private static var reader: AudioDeviceIOProcID?                   // what Core Audio calls with each piece of sound
    private static var tapFormat = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static let current = OSAllocatedUnfairLock<Backlog?>(initialState: nil)   // the sound waiting for the microphone; nil while the Mac is not heard

    /// Starts hearing what the Mac plays. If it cannot, `problem` is told why in a few words, once,
    /// and the microphone carries on alone.
    static func start(problem: @escaping @Sendable (String) -> Void) {
        queue.async {
            wanted = true
            end()
            guard allowed() != false else { return problem("NEEDS SYSTEM AUDIO") }   // asking now would put macOS's question up in the middle of a call
            let failed = begin()
            if failed != noErr { end(); Log.failed(.dictation, "the Mac's sound could not be heard", code: Int(failed)); problem("NO MAC SOUND") }
        }
    }

    /// Stops hearing it, and takes the tap and its device down. With `wait`, returns only once they are gone (for quitting).
    static func stop(wait: Bool = false) {
        let off = { wanted = false; end() }
        if wait { queue.sync(execute: off) } else { queue.async(execute: off) }
    }

    /// Adds what the Mac played into a buffer from the microphone. Called on the microphone's thread.
    static func mix(into sound: AVAudioPCMBuffer) {
        current.withLock { $0 }?.mix(into: sound)
    }

    /// Makes the tap and its device and starts reading. Gives noErr when it runs, or else Core Audio's number for the step
    /// that failed; `end` then takes down what was made.
    private static func begin() -> OSStatus {
        // Core Audio has a number of its own for every process that plays sound; Notch's is left out of the tap.
        var me = AudioObjectID(kAudioObjectUnknown), pid = getpid(), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var translate = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &translate, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &me)
        // Everything the Mac plays but Notch, mixed down to one channel, seen by Notch alone, and left playing as it is.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: me == kAudioObjectUnknown ? [] : [me])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { return status }
        // What the tap delivers: plain 32-bit numbers, at the rate the Mac plays at.
        var sound = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tap, &tapFormat, 0, nil, &size, &sound)
        guard status == noErr else { return status }
        guard sound.mSampleRate > 0, sound.mFormatID == kAudioFormatLinearPCM, sound.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              sound.mBitsPerChannel == 32 else { return kAudioDeviceUnsupportedFormatError }
        // Another output, or AirPods switching to their call mode, can change that rate: then all is made again to match.
        AudioObjectAddPropertyListenerBlock(tap, &tapFormat, queue, changed)
        // The device that holds only the tap: private, so no other app sees it, and gone when Notch quits.
        let composition: [String: Any] = [kAudioAggregateDeviceNameKey: "Notch", kAudioAggregateDeviceUIDKey: UUID().uuidString, kAudioAggregateDeviceIsPrivateKey: 1,
                                          kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]]]
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device)
        guard status == noErr else { return status }
        // Called on Core Audio's real-time thread, about every 10 ms, with the newest piece. It only copies it into the backlog.
        let backlog = Backlog(rate: sound.mSampleRate)
        status = AudioDeviceCreateIOProcIDWithBlock(&reader, device, nil, { _, input, _, _, _ in backlog.write(input) })
        guard status == noErr else { return status }
        // A device made a moment ago may not be ready to start yet: up to ten tries, 20 ms apart. This waits on `queue` only.
        for attempt in 1...10 {
            status = AudioDeviceStart(device, reader)
            if status == noErr { break }
            if attempt == 10 { return status }
            usleep(20_000)
        }
        current.withLock { $0 = backlog }
        return noErr
    }

    /// The tap's format changed. Runs on `queue`.
    private static let changed: AudioObjectPropertyListenerBlock = { _, _ in
        guard wanted else { return }   // stopped meanwhile
        end()
        let failed = begin()
        if failed != noErr { end(); Log.failed(.dictation, "the Mac's sound could not be heard after its format changed", code: Int(failed)) }
    }

    /// Takes down whatever `begin` made, newest first. Does nothing where nothing is there.
    private static func end() {
        current.withLock { $0 = nil }
        if let running = reader {
            AudioDeviceStop(device, running)
            AudioDeviceDestroyIOProcID(device, running)
            reader = nil
        }
        if device != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(device)
            device = kAudioObjectUnknown
        }
        if tap != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(tap, &tapFormat, queue, changed)
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
    }

    // macOS asks before an app may hear what the Mac plays (Privacy & Security, "System Audio Recording Only"), but
    // offers no public call to check or to ask. It asks by itself the first time a tap starts, so `ask` starts one for a
    // moment while Settings is open. To check, one call of its own permission service is looked up by name (in
    // `PrivateCalls`), as the open-source AudioCap does. If a later macOS drops it, Notch cannot tell, and simply tries.
    private static let service = "kTCCServiceAudioCapture" as CFString

    /// Whether Notch may hear what the Mac plays: true yes; false no, or not asked yet; nil when it cannot tell.
    static func allowed() -> Bool? {
        PrivateCalls.accessPreflight.map { $0(service, nil) == 0 }   // 0 allowed, 1 refused, 2 not asked yet
    }

    /// Lets macOS ask for the permission now, while Settings is open, so that it never asks in the middle of a call:
    /// a tap started for a moment, which is when macOS asks. macOS asks only once; after a no, only its own switch in
    /// Privacy & Security turns it on.
    static func ask() {
        guard allowed() != true else { return }   // given already: nothing to ask
        queue.async { if !wanted { _ = begin(); end() } }   // never while a dictation hears the Mac: `end` would take its tap down
    }
}
