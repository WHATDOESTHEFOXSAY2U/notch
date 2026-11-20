import AppKit
import AVFoundation
import CoreAudio
import IOKit
import Speech

/// What this Mac is and has: for the parts that need something a Mac may lack (a notch, a microphone, a camera, a
/// trackpad, the speech engine), for TEMP, whose sensors differ by chip, and for COPY REPORT. Every answer is read
/// afresh, since a camera or a trackpad can be plugged in at any time. Most take well under a millisecond, but the
/// first microphone check after launch takes about a tenth of a second, while macOS sets up its sound system for
/// Notch. So read an answer when it is needed (as Settings opens, at a key press), never on every frame. Read the
/// screens on the main thread.
enum Hardware {
    /// The Mac's model, e.g. "MacBookPro18,3".
    static var model: String { sysctl("hw.model") ?? "?" }
    /// The chip, e.g. "Apple M1 Pro".
    static var chip: String { sysctl("machdep.cpu.brand_string") ?? "?" }
    /// The chip's generation, e.g. "M1" for an M1, M1 Pro, Max or Ultra alike. Each generation names its temperature
    /// sensors its own way, so TEMP picks its keys by this. Nil for a chip that is not Apple's.
    static var chipFamily: String? { family(of: chip) }
    /// macOS's version, e.g. "27.2.1".
    static var macOSVersion: String { sysctl("kern.osproductversion") ?? "?" }
    /// macOS's build, e.g. "26B131". It changes with every update, the smallest included.
    static var macOSBuild: String { sysctl("kern.osversion") ?? "?" }

    // Screens.

    /// The screen with the notch, where the panel lives. Nil when no screen has one: a desktop Mac, or a closed lid.
    static var notchedScreen: NSScreen? { NSScreen.screens.first { notch(of: $0) != nil } }

    /// The notch on `screen`, in points; nil for a screen without one.
    static func notch(of screen: NSScreen) -> CGSize? {
        notch(width: screen.frame.width, left: screen.auxiliaryTopLeftArea?.width, right: screen.auxiliaryTopRightArea?.width, top: screen.safeAreaInsets.top)
    }

    /// The notch, from a screen's measures: as wide as the gap between the two parts of the menu bar on either side of
    /// it, and as tall as the band at the top that windows keep clear of. A screen without a notch has neither.
    static func notch(width: CGFloat, left: CGFloat?, right: CGFloat?, top: CGFloat) -> CGSize? {
        let sides = (left ?? 0) + (right ?? 0)
        return top > 0 && sides > 0 ? CGSize(width: width - sides, height: top) : nil
    }

    /// One screen, as COPY REPORT describes it.
    struct Display {
        var size: CGSize      // in points
        var scale: CGFloat    // pixels to a point: 2 on a Retina screen
        var notch: CGSize?    // in points; nil without one
        var builtIn: Bool     // the Mac's own screen
        var main: Bool        // the one System Settings calls the main display
    }

    /// Every screen, the main one first.
    static func displays() -> [Display] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return Display(size: screen.frame.size, scale: screen.backingScaleFactor, notch: notch(of: screen),
                           builtIn: number.map { CGDisplayIsBuiltin($0) != 0 } ?? false, main: index == 0)
        }
    }

    // The microphone and the camera. Listing them asks nothing: macOS asks only when one is used.

    /// Whether a microphone is connected: built in, USB, Bluetooth, or an iPhone's.
    static var hasMicrophone: Bool {
        soundDevices().contains { takesSoundIn($0) && isMicrophone(transport: transport(of: $0)) }
    }

    /// Whether a sound input connected this way is a microphone. Virtual and combined devices are not: they only pass
    /// sound from one app to another (a call app's own device, BlackHole, a device made of several others).
    static func isMicrophone(transport: UInt32) -> Bool {
        ![kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate].contains(transport)
    }

    /// Whether a camera is connected: built in, USB, or an iPhone's (macOS lists an iPhone as a built-in camera).
    static var hasCamera: Bool {
        !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices.isEmpty
    }

    /// Whether Apple's on-device speech engine runs on this Mac: DICTATE needs it. Apple publishes no list of the Macs
    /// it runs on; the engine answers for the Mac it is asked on.
    static var canDictate: Bool {
        guard #available(macOS 26, *) else { return false }
        return SpeechTranscriber.isAvailable
    }

    // Trackpads.

    /// One trackpad, as macOS describes it.
    struct Trackpad {
        var builtIn: Bool      // the MacBook's own, not a Magic Trackpad
        var forceTouch: Bool   // it feels how hard it is pressed
        var actuator: Bool     // it can play a click by itself; SWIPE's knocks use the built-in one's
    }

    /// Every trackpad connected now. A mouse is not one, a Magic Mouse included.
    static func trackpads() -> [Trackpad] {
        var drivers: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchTrackpadHIDEventDriver"), &drivers) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(drivers) }
        var found: [Trackpad] = []
        while case let driver = IOIteratorNext(drivers), driver != 0 {
            defer { IOObjectRelease(driver) }
            // The trackpad itself sits under its driver in the Mac's list of devices (the IORegistry), and says what it can do.
            func says(_ name: String) -> Bool {
                IORegistryEntrySearchCFProperty(driver, kIOServicePlane, name as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? Bool == true
            }
            found.append(Trackpad(builtIn: says("MT Built-In"), forceTouch: says("ForceSupported"), actuator: says("ActuationSupported")))
        }
        return found
    }

    /// Whether any trackpad is connected: SWIPE needs one.
    static var hasTrackpad: Bool { !trackpads().isEmpty }
    /// Whether a connected trackpad feels how hard it is pressed (Force Touch).
    static var hasForceTouch: Bool { trackpads().contains { $0.forceTouch } }

    // The chip's name, taken apart.

    /// The generation in a chip's name: "Apple M1 Pro" is "M1", "Apple M3 Max" is "M3", "Apple A18 Pro" is "A18".
    /// Nil for a name that is not "Apple" followed by a letter and a number.
    static func family(of chip: String) -> String? {
        let words = chip.split(separator: " ")
        guard words.count > 1, words[0] == "Apple" else { return nil }
        let family = words[1]
        guard family.count > 1, family.first?.isLetter == true, family.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return String(family)
    }

    // Reading the Mac.

    /// A text the kernel keeps, by its name (`sysctl -a` lists them all). Nil if there is no such name.
    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Every sound device macOS knows: outputs, inputs, and both.
    private static func soundDevices() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    /// Whether `device` takes sound in: it has at least one input stream.
    private static func takesSoundIn(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// How `device` is connected, as a four-letter code: "bltn" built in, "usb " USB, "virt" virtual, and so on.
    private static func transport(of device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return transport
    }
}
