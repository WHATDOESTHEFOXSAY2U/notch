import CoreGraphics
import Testing
@testable import Logic

// HyperState.swift: pure state machine for Caps Lock as a hyper key, including stuck-key recovery
// when an F18 key-up is dropped and the circuit breaker for repeated tapDisabledByTimeout events.

private let f18: Int64 = 79
private let keyD: Int64 = 2
private let keyA: Int64 = 0

@Test func normalHyperKeyPressAndRelease() {
    var state = HyperState()
    // Plain key without Caps Lock passes untouched.
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 1) == .pass)
    // Caps Lock (F18) down is swallowed and enters held state.
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 2) == .swallow)
    #expect(state.held)
    // Another key while F18 is held gets ⌃⌥⇧⌘.
    #expect(state.handle(type: .keyDown, keyCode: keyD, f18KeyCode: f18, now: 2.1) == .addHyper)
    #expect(state.handle(type: .keyUp, keyCode: keyD, f18KeyCode: f18, now: 2.2) == .addHyper)
    // F18 release clears held state and is swallowed.
    #expect(state.handle(type: .keyUp, keyCode: f18, f18KeyCode: f18, now: 2.3) == .swallow)
    #expect(!state.held)
    // Next key passes untouched again.
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 2.4) == .pass)
}

@Test func secureInputAndIdleTimeoutPreventStuckHyperKey() {
    var state = HyperState()
    // Caps Lock pressed, then a shortcut opens a password field (Secure Input turns on and eats F18 keyUp).
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1) == .swallow)
    #expect(state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 1.5, secureInput: true) == .pass)
    #expect(!state.held)
    // Even if F18 is pressed during Secure Input, F18 is swallowed without latching held.
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1.8, secureInput: true) == .swallow)
    #expect(!state.held)

    // If F18 keyUp is lost for any other reason, idle timeout expires cleanly instead of breaking typing forever.
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 10) == .swallow)
    #expect(state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 10 + HyperState.maxIdleHold + 0.1) == .pass)
    #expect(!state.held)
}

@Test func tapDisabledClearsHeldAndCircuitBreakerStopsFreezeLoops() {
    var state = HyperState()
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1) == .swallow)
    // User-initiated disable clears held and never re-enables.
    #expect(state.handle(type: .tapDisabledByUserInput, keyCode: -1, f18KeyCode: f18, now: 2) == .pass)
    #expect(!state.held)

    // Up to maxTimeouts timeouts within timeoutWindow re-enable cleanly.
    for i in 1...HyperState.maxTimeouts {
        #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: Double(10 + i)) == .reenable)
    }
    // One more inside the same window trips the breaker so Notch never loops keyboard freezes.
    #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: 15) == .tripTimeoutLimit)

    // After the window expires, old timeouts age out and a single isolated timeout re-enables again.
    #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: 40) == .reenable)
}
