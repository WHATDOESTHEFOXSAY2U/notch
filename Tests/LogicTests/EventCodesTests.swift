import Testing
@testable import Logic

// EventCodes.swift: each name is the very number the code compared with before it had one.

@Test func eventCodesAreTheOldNumbers() {
    #expect(EventCodes.escape == UInt16(53))
    #expect(EventCodes.gesture == UInt32(29))
    #expect([EventCodes.scrollMayBegin, EventCodes.scrollBegan, EventCodes.scrollChanged, EventCodes.scrollEnded, EventCodes.scrollCancelled]
            == [128, 1, 2, 4, 8] as [Int64])
    #expect([EventCodes.glideNone, EventCodes.glideEnd] == [0, 3] as [Int64])
}
