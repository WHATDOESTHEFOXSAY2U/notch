import Foundation
import Testing
@testable import Logic

// Preset.swift: the arithmetic of a smaller copy: the picture each size keeps, the bits WhatsApp's limit leaves, what
// a copy will weigh, and where it goes. No video is opened or written.

private let k4 = CGSize(width: 3840, height: 2160)

/// `size` fitted into 1920 × 1080, as BALANCED does, as [width, height].
private func fitted(_ size: CGSize) -> [Int] {
    let fit = Preset.fit(size, long: 1920, short: 1080)
    return [fit.width, fit.height]
}

@Test func bestKeepsThePictureAndBalancedFits1080p() {
    let best = Preset.best.plan(size: k4, seconds: 92, sound: true)
    #expect([best.width, best.height] == [3840, 2160] as [Int])
    #expect(best.quality != nil)
    #expect(best.bits == nil)
    #expect(!best.h264)
    let balanced = Preset.balanced.plan(size: k4, seconds: 92, sound: true)
    #expect([balanced.width, balanced.height] == [1920, 1080] as [Int])
    #expect(balanced.quality == 0.45)   // the copy REC's card has always made
}

@Test func fitNeverScalesUpAndKeepsSidesEven() {
    #expect(fitted(CGSize(width: 1280, height: 720)) == [1280, 720])
    #expect(fitted(CGSize(width: 2998, height: 1946)) == [1662, 1080])
    #expect(fitted(CGSize(width: 1001, height: 501)) == [1000, 500])
}

@Test func aTallVideoIsFittedAsItStands() {
    #expect(fitted(CGSize(width: 2160, height: 3840)) == [1080, 1920])
}

@Test func whatsappIsH264At720pAndThirtyPicturesASecond() {
    let plan = Preset.whatsapp.plan(size: k4, seconds: 92, sound: true)
    #expect(plan.h264)
    #expect([plan.width, plan.height] == [1280, 720] as [Int])
    #expect(plan.rate == 30)
    #expect(plan.bits == Int(1280 * 720 * 4.4))   // a short video gets the bits the picture can use, not all the limit allows
    #expect(plan.fits)
}

@Test(arguments: [240.0, 360, 600, 780])
func whatsappStaysUnderItsLimit(seconds: Double) {
    let plan = Preset.whatsapp.plan(size: k4, seconds: seconds, sound: true)
    #expect(plan.fits)
    #expect(Preset.weight(bits: plan.bits ?? 0, seconds: seconds, sound: true) < Preset.whatsappLimit)
}

@Test func whatsappDropsTo480pWhenTheBitsRunShort() {
    #expect(Preset.whatsapp.plan(size: k4, seconds: 300, sound: true).height == 720)
    #expect(Preset.whatsapp.plan(size: k4, seconds: 600, sound: true).height == 480)
}

@Test func whatsappSaysWhenAVideoIsTooLong() {
    let plan = Preset.whatsapp.plan(size: k4, seconds: 3600, sound: true)
    #expect(!plan.fits)
    #expect(plan.bits == 500_000)   // still worth watching, and sent as a document
    #expect(Preset.weight(bits: plan.bits ?? 0, seconds: 3600, sound: true) > Preset.whatsappLimit)
}

@Test func aSmallPictureGetsNoMoreBitsThanItCanUse() {
    let plan = Preset.whatsapp.plan(size: CGSize(width: 320, height: 240), seconds: 10, sound: false)
    #expect([plan.width, plan.height] == [320, 240] as [Int])
    #expect(plan.bits == Int(320 * 240 * 4.4))
    #expect(plan.fits)
}

@Test func picturesAreNamedByTheirShortSide() {
    #expect(Preset.label(width: 3840, height: 2160) == "4K")
    #expect(Preset.label(width: 1920, height: 1080) == "1080P")
    #expect(Preset.label(width: 1080, height: 1920) == "1080P")   // however the phone was held
    #expect(Preset.label(width: 1280, height: 720) == "720P")
}

@Test func weightAtFixedBits() {
    #expect(Preset.weight(bits: 4_000_000, seconds: 10, sound: false) == 5_000_000)
    #expect(Preset.weight(bits: 4_000_000, seconds: 10, sound: true) == 5_120_000)
}

@Test func estimateCountsFullPicturesApart() {
    // Three trial pieces: a full picture of 200 kB each, then 59 pictures of 5 kB. The whole: 60 s at 60 a second.
    let guess = Preset.estimate(key: 200_000, others: 3 * 59 * 5_000, frames: 3 * 59, total: 3600, seconds: 60, sound: false)
    // 6 full pictures and 3,594 others, plus 1%. Counting the trial pieces as they stand would say 30 MB.
    #expect(guess == Int(Double(6 * 200_000 + 3594 * 5_000) * 1.01))
}

@Test func estimateAddsTheSound() {
    let silent = Preset.estimate(key: 100_000, others: 100_000, frames: 100, total: 600, seconds: 20, sound: false)
    let heard = Preset.estimate(key: 100_000, others: 100_000, frames: 100, total: 600, seconds: 20, sound: true)
    #expect(abs(heard - silent - Int(Double(96_000 / 8 * 20) * 1.01)) <= 1)
}

@Test func savedIsAWholePercentAndNeverNegative() {
    #expect(Preset.saved(38, of: 248) == 85)
    #expect(Preset.saved(248, of: 248) == 0)
    #expect(Preset.saved(300, of: 248) == 0)   // a larger copy saved nothing
    #expect(Preset.saved(10, of: 0) == 0)
}

@Test func theCopySitsBesideTheOriginalAndNeverReplacesAFile() {
    let file = URL(fileURLWithPath: "/Videos/Trip.mov")
    #expect(Preset.target(for: file) { _ in false }.path == "/Videos/Trip small.mp4")
    let taken: Set = ["/Videos/Trip small.mp4", "/Videos/Trip small 2.mp4"]
    #expect(Preset.target(for: file) { taken.contains($0.path) }.path == "/Videos/Trip small 3.mp4")
}

@Test func onlyVideosTheMacCanWriteAgainAreCompressed() {
    #expect(Preset.reads(URL(fileURLWithPath: "/a/Clip.MOV")))
    #expect(Preset.reads(URL(fileURLWithPath: "/a/clip.mp4")))
    #expect(!Preset.reads(URL(fileURLWithPath: "/a/clip.mkv")))   // Scribe reads it; the Mac's own encoder does not
    #expect(!Preset.reads(URL(fileURLWithPath: "/a/talk.m4a")))
}
