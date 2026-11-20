import Testing
@testable import Logic

// Launch.swift: when the warm helper runs. Nothing is started here: TEXT's state and the builds are given.

@Test func theWarmHelperRunsOnceForEachMacOSBuild() {
    #expect(Launch.shouldWarm(textOn: true, warmedFor: nil, build: "26B131"))            // never run yet
    #expect(!Launch.shouldWarm(textOn: true, warmedFor: "26B131", build: "26B131"))      // run to the end for this macOS
    #expect(Launch.shouldWarm(textOn: true, warmedFor: "26B131", build: "26C5023a"))     // macOS updated since
}

@Test func theWarmHelperWaitsWhileTextIsOff() {
    #expect(!Launch.shouldWarm(textOn: false, warmedFor: nil, build: "26B131"))
    #expect(!Launch.shouldWarm(textOn: false, warmedFor: "26B131", build: "26C5023a"))
}
