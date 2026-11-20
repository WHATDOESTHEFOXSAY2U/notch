import AppKit
import Carbon.HIToolbox

/// Numbers that macOS puts in key, scroll and gesture events, by the names Apple gives them.
/// Each is the very number the code compared with before it had a name.
enum EventCodes {
    /// The Esc key, as `NSEvent.keyCode` gives it (53).
    static let escape = UInt16(kVK_Escape)

    /// The type of a trackpad gesture event, pinches among them (29). Apple names it only for `NSEvent`, so an event
    /// tap gets it as a bare number. Not 30: those are the Dock's own (Mission Control, the swipe between Spaces).
    static let gesture = UInt32(NSEvent.EventType.gesture.rawValue)

    // A trackpad scroll's phase, as `scrollWheelEventScrollPhase` gives it.
    static let scrollMayBegin = Int64(CGScrollPhase.mayBegin.rawValue)     // 128: fingers down
    static let scrollBegan = Int64(CGScrollPhase.began.rawValue)           // 1: they start moving
    static let scrollChanged = Int64(CGScrollPhase.changed.rawValue)       // 2: moving on
    static let scrollEnded = Int64(CGScrollPhase.ended.rawValue)           // 4: lifted
    static let scrollCancelled = Int64(CGScrollPhase.cancelled.rawValue)   // 8: called off

    // The glide after the fingers lift, as `scrollWheelEventMomentumPhase` gives it.
    static let glideNone = Int64(CGMomentumScrollPhase.none.rawValue)      // 0: no glide
    static let glideEnd = Int64(CGMomentumScrollPhase.end.rawValue)        // 3: the glide's last event
}
