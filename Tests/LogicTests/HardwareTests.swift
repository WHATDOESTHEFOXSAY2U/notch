import CoreAudio
import Foundation
import Testing
@testable import Logic

// Hardware.swift: the arithmetic and the rules, with the Mac's answers given. Nothing here reads this Mac.

@Test func aChipsFamilyIsTheGenerationInItsName() {
    #expect(Hardware.family(of: "Apple M1") == "M1")
    #expect(Hardware.family(of: "Apple M1 Pro") == "M1")   // the name this Mac's kernel gives (machdep.cpu.brand_string)
    #expect(Hardware.family(of: "Apple M2 Max") == "M2")
    #expect(Hardware.family(of: "Apple M3 Ultra") == "M3")
    #expect(Hardware.family(of: "Apple M4 Pro") == "M4")
    #expect(Hardware.family(of: "Apple M5") == "M5")
    #expect(Hardware.family(of: "Apple A18 Pro") == "A18")   // the MacBook Neo
    #expect(Hardware.family(of: "Apple M12 Max") == "M12")
}

@Test func otherChipsHaveNoFamily() {
    #expect(Hardware.family(of: "Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz") == nil)
    #expect(Hardware.family(of: "Apple processor") == nil)
    #expect(Hardware.family(of: "Apple M") == nil)
    #expect(Hardware.family(of: "Apple") == nil)
    #expect(Hardware.family(of: "?") == nil)   // what `chip` says when the kernel gives no name
    #expect(Hardware.family(of: "") == nil)
}

@Test func theNotchIsTheGapBetweenTheMenuBarsTwoParts() {
    #expect(Hardware.notch(width: 1512, left: 660, right: 667, top: 32) == CGSize(width: 185, height: 32))
    #expect(Hardware.notch(width: 1728, left: 769.5, right: 769.5, top: 38) == CGSize(width: 189, height: 38))
}

@Test func aScreenWithoutANotchHasNone() {
    #expect(Hardware.notch(width: 1920, left: nil, right: nil, top: 0) == nil)   // an external display
    #expect(Hardware.notch(width: 1920, left: 0, right: 0, top: 0) == nil)
    #expect(Hardware.notch(width: 1512, left: nil, right: nil, top: 24) == nil)   // a band at the top, but no menu bar on either side
    #expect(Hardware.notch(width: 1512, left: 660, right: 667, top: 0) == nil)
}

@Test func onlyRealMicrophonesCount() {
    for transport in [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
                      kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeContinuityCaptureWireless, kAudioDeviceTransportTypeThunderbolt] {
        #expect(Hardware.isMicrophone(transport: transport))
    }
    // Devices that only pass sound between apps.
    for transport in [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate] {
        #expect(!Hardware.isMicrophone(transport: transport))
    }
}

@Test func notchEntryAcceptsOnlyTheClosedNotchAndNeverNearbyScreenArea() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let notch = CGSize(width: 185, height: 32)   // midX = 756, notch spans x = 663.5...848.5, y = 950...982
    // Inside the physical notch, including pushed flush against the top screen edge (y == maxY).
    #expect(Hardware.inNotchEntry(mouse: CGPoint(x: 756, y: 982), screen: screen, notch: notch))
    #expect(Hardware.inNotchEntry(mouse: CGPoint(x: 756, y: 960), screen: screen, notch: notch))
    #expect(Hardware.inNotchEntry(mouse: CGPoint(x: 670, y: 952), screen: screen, notch: notch))
    // Nearby points inside the 500×135 open-panel footprint must NEVER trigger opening when closed.
    #expect(!Hardware.inNotchEntry(mouse: CGPoint(x: 756, y: 945), screen: screen, notch: notch))   // 5 pt below the notch
    #expect(!Hardware.inNotchEntry(mouse: CGPoint(x: 756, y: 880), screen: screen, notch: notch))   // over browser tabs / toolbar
    #expect(!Hardware.inNotchEntry(mouse: CGPoint(x: 560, y: 970), screen: screen, notch: notch))   // menu bar beside the notch
    #expect(!Hardware.inNotchEntry(mouse: CGPoint(x: 664, y: 970), screen: screen, notch: notch))   // outer 3 pt corner margin
}

@Test func notchActiveMatchesCurrentExpandedPanelAndCushion() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let panel = CGSize(width: 500, height: 134)   // spans x = 506...1006, y = 848...982 (plus 4 pt cushion)
    #expect(Hardware.inNotchActive(mouse: CGPoint(x: 756, y: 982), screen: screen, panel: panel))
    #expect(Hardware.inNotchActive(mouse: CGPoint(x: 510, y: 850), screen: screen, panel: panel))
    #expect(Hardware.inNotchActive(mouse: CGPoint(x: 1009, y: 845), screen: screen, panel: panel))  // within 4 pt cushion
    #expect(!Hardware.inNotchActive(mouse: CGPoint(x: 756, y: 840), screen: screen, panel: panel))  // below open panel
    #expect(!Hardware.inNotchActive(mouse: CGPoint(x: 495, y: 920), screen: screen, panel: panel))  // left of open panel
}
