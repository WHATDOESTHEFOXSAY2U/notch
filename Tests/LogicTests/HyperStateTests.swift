import CoreGraphics
import Testing
@testable import Logic

// HyperState.swift: pure state machine for Caps Lock as a hyper key, including stuck-key recovery
// when an F18 key-up is dropped (even while the user continues typing!) and the circuit breaker for
// repeated tapDisabledByTimeout events.

private let f18: Int64 = 79
private let keyD: Int64 = 2
private let keyA: Int64 = 0

@Test func normalHyperKeyPressAndRelease() {
    var state = HyperState()
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 1) == .pass)
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 2) == .swallow)
    #expect(state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyD, f18KeyCode: f18, now: 2.1) == .addHyper)
    #expect(state.handle(type: .keyUp, keyCode: keyD, f18KeyCode: f18, now: 2.2) == .addHyper)
    #expect(state.handle(type: .keyUp, keyCode: f18, f18KeyCode: f18, now: 2.3) == .swallow)
    #expect(!state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 2.4) == .pass)
}

@Test func secureInputAndContinuousTypingRecoverFromMissedF18KeyUp() {
    var state = HyperState()
    // Caps Lock pressed, then a shortcut opens a password field (Secure Input turns on and eats F18 keyUp).
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1) == .swallow)
    #expect(state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 1.5, secureInput: true) == .pass)
    #expect(!state.held)
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1.8, secureInput: true) == .swallow)
    #expect(!state.held)

    // Even if F18 keyUp is lost without Secure Input AND the user keeps typing every half-second,
    // non-F18 keys never extend `lastF18`, so normal typing comes back automatically past maxIdleHold.
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 10) == .swallow)
    #expect(state.held)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 11.0) == .addHyper)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 12.0) == .addHyper)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 13.0) == .addHyper)
    #expect(state.handle(type: .keyDown, keyCode: keyA, f18KeyCode: f18, now: 10 + HyperState.maxIdleHold + 0.1) == .pass)
    #expect(!state.held)

    // Hardware auto-repeat F18 keyDowns while physically holding Caps Lock keep `held` alive cleanly.
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 20) == .swallow)
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 23) == .swallow)
    #expect(state.handle(type: .keyDown, keyCode: keyD, f18KeyCode: f18, now: 25) == .addHyper)
    #expect(state.handle(type: .keyUp, keyCode: f18, f18KeyCode: f18, now: 25.1) == .swallow)
    #expect(!state.held)
}

@Test func tapDisabledClearsHeldAndCircuitBreakerStopsFreezeLoops() {
    var state = HyperState()
    #expect(state.handle(type: .keyDown, keyCode: f18, f18KeyCode: f18, now: 1) == .swallow)
    #expect(state.handle(type: .tapDisabledByUserInput, keyCode: -1, f18KeyCode: f18, now: 2) == .disable)
    #expect(!state.held)

    for i in 1...HyperState.maxTimeouts {
        #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: Double(10 + i)) == .reenable)
    }
    #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: 15) == .tripTimeoutLimit)
    #expect(state.handle(type: .tapDisabledByTimeout, keyCode: -1, f18KeyCode: f18, now: 40) == .reenable)
}
