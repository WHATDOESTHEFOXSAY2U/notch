import AppKit
import Testing
@testable import Logic

// Place.swift: where a swipe can send a window, in a screen one unit wide and one unit tall, from the top left.

let screen = CGRect(x: 0, y: 0, width: 1, height: 1)

@Test func halvesMeetAndFillTheScreen() {
    #expect(Place.left.unit.maxX == Place.right.unit.minX)
    #expect(Place.left.unit.union(Place.right.unit) == screen)
}

@Test func quartersMeetAndFillTheScreen() {
    #expect(Place.topLeft.unit.maxX == Place.topRight.unit.minX)
    #expect(Place.topLeft.unit.maxY == Place.lowLeft.unit.minY)
    #expect(Place.lowLeft.unit.maxX == Place.lowRight.unit.minX)
    #expect(Place.topRight.unit.maxY == Place.lowRight.unit.minY)
    #expect([Place.topLeft, .topRight, .lowLeft, .lowRight].map(\.unit).reduce(.null) { $0.union($1) } == screen)
}

@Test func fillFullAndCloseTakeTheWholeScreen() {
    #expect(Place.fill.unit == screen && Place.full.unit == screen && Place.close.unit == screen)
}

@Test func onlyFullScreenAndClosingTakeTheWholePicture() {
    #expect(Place.full.whole && Place.close.whole)
    #expect(![Place.left, .right, .fill, .minimize, .topLeft, .topRight, .lowLeft, .lowRight].contains { $0.whole })
}

@Test func minimizingLightsABarAtTheBottomLikeTheDock() {
    #expect(Place.minimize.unit.maxY == 1)
    #expect(Place.minimize.unit.midX == 0.5)
}

@Test func theWindowsOwnButtonsKeepTheirColors() {
    #expect(Place.full.color == .systemGreen)
    #expect(Place.minimize.color == .systemYellow)
    #expect(Place.close.color == .systemRed)
    #expect([Place.left, .right, .fill, .topLeft, .topRight, .lowLeft, .lowRight].allSatisfy { $0.color == .white })
}
