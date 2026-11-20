import ApplicationServices
import Foundation

/// Every call Notch makes that is not in Apple's published list, in one place, so they can all be checked at once.
/// Each is looked up by name while Notch runs, never linked: on a macOS without it Notch still starts, the lookup
/// gives nil, and the part that uses it carries on as its line below says. Nothing here is looked up until first used.
enum PrivateCalls {
    /// Looks up `name` in `library`: by default every library Notch has loaded already (-2 asks for that).
    /// Nil if it is not there, or if the library itself could not be loaded.
    static func find<T>(_ name: String, in library: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2)) -> T? {
        library.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: T.self) }
    }

    // The window server, as yabai and Amethyst use it (Spaces, Pointer).
    /// Notch's own connection to the window server; the calls below take it first. Without it: no Space counts as
    /// full screen, and the arrow stays visible during a swipe.
    static let connection: (@convention(c) () -> Int32)? = find("_CGSDefaultConnection")
    /// The Space a display shows now. Without it: the Space in front is asked instead.
    static let displaySpace: (@convention(c) (Int32, CFString) -> UInt64)? = find("CGSManagedDisplayGetCurrentSpace")
    /// The Space in front, for when all displays share one. Without it, and without the one above: not full screen.
    static let activeSpace: (@convention(c) (Int32) -> UInt64)? = find("CGSGetActiveSpace")
    /// What kind of Space it is: 0 an ordinary desktop, 4 full screen. Without it: not full screen.
    static let spaceKind: (@convention(c) (Int32, UInt64) -> Int32)? = find("CGSSpaceGetType")
    /// Sets something about a connection: Notch asks to hide the pointer while it is not the app in front
    /// ("SetsCursorInBackground"). Without it: the arrow stays visible on top of the swipe's picture.
    static let setConnectionProperty: (@convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32)? = find("CGSSetConnectionProperty")

    // Accessibility, as Rectangle, yabai, AeroSpace and AltTab use it (Windows).
    /// The window server's number for an app's window. Without it: windows are found by their frames.
    static let windowNumber: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = find("_AXUIElementGetWindow")

    // The trackpad's actuator, in MultitouchSupport (Knock). Without any of these, or without the library: the
    // public haptic call instead. Without `actuatorClose` alone, the trackpad is not let go of when idle.
    private static let multitouch = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    static let actuatorCreate: (@convention(c) (UInt64) -> Unmanaged<CFTypeRef>?)? = find("MTActuatorCreateFromDeviceID", in: multitouch)
    static let actuatorOpen: (@convention(c) (CFTypeRef) -> Int32)? = find("MTActuatorOpen", in: multitouch)
    static let actuatorClose: (@convention(c) (CFTypeRef) -> Int32)? = find("MTActuatorClose", in: multitouch)
    static let actuate: (@convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32)? = find("MTActuatorActuate", in: multitouch)

    // macOS's permission service, as the open-source AudioCap uses it: in MacSound, for hearing what the Mac plays,
    // and in Permissions, for the PERMISSIONS block in Settings and the RESTART key.
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    /// Whether a permission is given: 0 yes, 1 no, 2 not asked yet. It never asks. Without it: MacSound cannot tell,
    /// and simply tries; Permissions tells SCREEN and ACCESSIBILITY only ON or OFF, and cannot tell SYSTEM AUDIO at all;
    /// SHOT, TEXT and REC cannot see a new Screen Recording yes, so they never offer the RESTART key.
    static let accessPreflight: (@convention(c) (CFString, CFDictionary?) -> Int32)? = find("TCCAccessPreflight", in: tcc)

    // Processes, as Activity Monitor counts them (Stats).
    private static let responsible: (@convention(c) (pid_t) -> pid_t)? = find("responsibility_get_pid_responsible_for_pid")

    /// The app a process belongs to (a browser tab's process belongs to the browser). Without the call, each
    /// process counts for itself.
    static func owner(of pid: pid_t) -> pid_t { responsible?(pid) ?? pid }
}
