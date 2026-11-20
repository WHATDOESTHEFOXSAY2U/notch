import CoreAudio
import Foundation

/// Silences the Mac's own sound while you dictate, so the microphone hears only you, and gives it
/// back afterwards. Sound that was already off stays off, and an output that has no mute is left alone.
/// Not used while the Mac's sound is being heard too: that sound must stay on.
/// While the sound is off, the settings also hold a note of which output it is, so that if Notch stops
/// without giving the sound back (a crash, a forced quit), its next launch does: see `recover`.
enum Quiet {
    private static var silenced: AudioDeviceID?   // the output this silenced, so the same one gets its sound back
    private static var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    static func begin() {
        guard silenced == nil, UserDefaults.standard.bool(forKey: Prefs.hush) else { return }   // on unless switched off in Settings: it starts on (Prefs)
        var device = AudioDeviceID(0), muted: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)   // a device's number and its mute are both 32 bits
        var which = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &which, 0, nil, &size, &device) == noErr,
              AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted) == noErr, muted == 0 else { return }
        // The note is written before the sound goes off, so a crash at any moment after this is put right at the next launch.
        // It holds the output's UID: the name macOS keeps for it across restarts, unlike its number.
        var uid: Unmanaged<CFString>?, uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var name = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &name, 0, nil, &uidSize, &uid) == noErr, let uid { UserDefaults.standard.set(uid.takeRetainedValue() as String, forKey: Prefs.mutedOutput) }
        muted = 1
        if AudioObjectSetPropertyData(device, &mute, 0, nil, size, &muted) == noErr { silenced = device } else { UserDefaults.standard.removeObject(forKey: Prefs.mutedOutput) }
    }

    static func end() {
        guard let device = silenced else { return }
        silenced = nil
        var off: UInt32 = 0
        AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
        UserDefaults.standard.removeObject(forKey: Prefs.mutedOutput)   // nothing left for the next launch to put right
    }

    /// Called once at launch, before any dictation. A note still there means Notch stopped last time with the
    /// sound off: if that output is still silent, it gets its sound back. Either way the note is then cleared.
    static func recover() {
        guard silenced == nil, let uid = UserDefaults.standard.string(forKey: Prefs.mutedOutput) else { return }   // a note this launch wrote is not a leftover
        defer { UserDefaults.standard.removeObject(forKey: Prefs.mutedOutput) }   // looked at once, then cleared, whatever is found below
        var device = AudioDeviceID(0), muted: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        var find = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let found = withUnsafePointer(to: uid as CFString) {   // macOS looks up the output's current number from its UID
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &find, UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        guard found == noErr, device != kAudioObjectUnknown,   // unknown: that output is not connected now
              AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted) == noErr, muted != 0 else { return }   // or its sound is already on
        muted = 0
        AudioObjectSetPropertyData(device, &mute, 0, nil, size, &muted)
    }
}
