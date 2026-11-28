import CoreGraphics

/// Pure state machine for Caps Lock as a hyper key (F18 down adds ⌃⌥⇧⌘ to other keys).
/// Kept free of Mach ports, WindowServer IPC, and IOHID so stuck-key recovery across Secure Event Input,
/// missed key-ups, and repeated timeouts can be tested directly without permissions.
struct HyperState {
    enum Action: Equatable {
        case pass              // pass the event through untouched
        case swallow           // swallow F18 itself
        case addHyper          // attach ⌃⌥⇧⌘ to the event and pass through
        case disable           // tap disabled by macOS user input: stop and restore Caps Lock
        case reenable          // tap disabled by timeout: re-enable (rate-limited)
        case tripTimeoutLimit  // too many timeouts in a short window: stop instead of looping freezes
    }

    private(set) var held = false
    private var lastF18 = 0.0           // timestamp of the most recent F18 keyDown (initial or auto-repeat)
    private var timeouts: [Double] = [] // timestamps (seconds) of recent tapDisabledByTimeout events

    /// Maximum seconds since the last F18 keyDown before a stranded `held` state auto-expires.
    /// Crucially, non-F18 keys never extend `lastF18`, so even continuous typing after a lost F18 keyUp
    /// recovers automatically in a few seconds instead of staying stuck until the user stops typing.
    static let maxIdleHold = 3.5

    /// More than this many timeouts within `timeoutWindow` seconds trips the breaker instead of endlessly
    /// re-enabling a stalling keyboard tap.
    static let maxTimeouts = 4
    static let timeoutWindow = 10.0

    mutating func reset() {
        held = false
        lastF18 = 0
    }

    /// Decides what to do for one keyboard tap event.
    /// `secureInput` reflects `IsSecureEventInputEnabled()`: while Secure Input is active, macOS withholds
    /// keyUps from event taps, so `held` is never latched across a secure field.
    mutating func handle(
        type: CGEventType,
        keyCode: Int64,
        f18KeyCode: Int64,
        now: Double,
        secureInput: Bool = false
    ) -> Action {
        if type == .tapDisabledByTimeout {
            reset()
            timeouts.removeAll { now - $0 > HyperState.timeoutWindow }
            timeouts.append(now)
            return timeouts.count <= HyperState.maxTimeouts ? .reenable : .tripTimeoutLimit
        }
        if type == .tapDisabledByUserInput {
            reset()
            return .disable
        }
        if secureInput {
            reset()
            return keyCode == f18KeyCode ? .swallow : .pass
        }
        if keyCode == f18KeyCode {
            if type == .keyDown {
                held = true
                lastF18 = now
            } else if type == .keyUp {
                reset()
            }
            return .swallow
        }
        if held {
            if now - lastF18 > HyperState.maxIdleHold {
                reset()
                return .pass
            }
            return .addHyper
        }
        return .pass
    }
}
