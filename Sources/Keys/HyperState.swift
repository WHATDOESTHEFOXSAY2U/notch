import CoreGraphics

/// Pure state machine for Caps Lock as a hyper key (F18 down adds ⌃⌥⇧⌘ to other keys).
/// Kept free of Mach ports, WindowServer IPC, and IOHID so stuck-key recovery across Secure Event Input,
/// missed key-ups, idle holds, and repeated timeouts can be tested directly without permissions.
struct HyperState {
    enum Action: Equatable {
        case pass              // pass the event through untouched
        case swallow           // swallow F18 itself
        case addHyper          // attach ⌃⌥⇧⌘ to the event and pass through
        case reenable          // tap disabled by timeout: re-enable (rate-limited)
        case tripTimeoutLimit  // too many timeouts in a short window: stop instead of looping freezes
    }

    private(set) var held = false
    private var lastActivity = 0.0      // timestamp of F18 keyDown or most recent hyper chord key
    private var timeouts: [Double] = [] // timestamps (seconds) of recent tapDisabledByTimeout events

    /// Maximum silent gap (seconds) with zero key activity before a stranded `held` state auto-expires,
    /// ensuring a dropped F18 keyUp can never leave normal typing poisoned with ⌃⌥⇧⌘.
    static let maxIdleHold = 6.0

    /// More than this many timeouts within `timeoutWindow` seconds trips the breaker instead of endlessly
    /// re-enabling a stalling keyboard tap.
    static let maxTimeouts = 4
    static let timeoutWindow = 10.0

    mutating func reset() {
        held = false
        lastActivity = 0
    }

    /// Decides what to do for one keyboard tap event, with zero synchronous IPC inside the tap.
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
            return .pass
        }
        if secureInput {
            reset()
            return keyCode == f18KeyCode ? .swallow : .pass
        }
        if keyCode == f18KeyCode {
            if type == .keyDown {
                held = true
                lastActivity = now
            } else if type == .keyUp {
                reset()
            }
            return .swallow
        }
        if held {
            if now - lastActivity > HyperState.maxIdleHold {
                reset()
                return .pass
            }
            lastActivity = now
            return .addHyper
        }
        return .pass
    }
}
