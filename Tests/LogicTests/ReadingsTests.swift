import Foundation
import Testing
@testable import Logic

// The panel's readings: memory and CPU in Stats.swift, the SMC's keys and blocks in SMC.swift. Stats' lines read the
// machine where they are, so their arithmetic is copied here, word for word (see CopiedLinesTests.swift). SMC's are
// tested where they are. Nothing here reads the machine or opens the SMC.

/// Memory in use, in percent of the RAM, from the kernel's page counts.
func memoryInUse(_ vm: vm_statistics64) -> Double {
    var mem = 0.0
    // Copied from Panel/Stats.swift:
    let pages = (vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) + vm.wire_count + vm.compressor_page_count
    mem = Double(pages) * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100
    // End of copy.
    return mem
}

/// The CPU reading, from the kernel's tick counts: user, system, idle, nice.
struct CPUReading {
    var cpu = 0.0
    var lastTicks = (busy: 0.0, total: 0.0)

    mutating func take(_ t: (natural_t, natural_t, natural_t, natural_t)) {
        // Copied from Panel/Stats.swift:
        let busy = Double(t.0) + Double(t.1) + Double(t.3), total = busy + Double(t.2)
        if total - lastTicks.total >= 50 {
            cpu = (busy - lastTicks.busy) / (total - lastTicks.total) * 100
            lastTicks = (busy, total)
        }
        // End of copy.
    }
}

/// Page counts for `percent` of this Mac's RAM in use: half of it as app memory, a quarter wired, a quarter compressed.
func pages(inUse percent: Int, purgeable: natural_t = 0, free: natural_t = 0) -> vm_statistics64 {
    let all = Int(ProcessInfo.processInfo.physicalMemory) / Int(vm_kernel_page_size), used = all * percent / 100
    var vm = vm_statistics64()
    vm.internal_page_count = natural_t(used / 2) + purgeable
    vm.purgeable_count = purgeable
    vm.wire_count = natural_t(used / 4)
    vm.compressor_page_count = natural_t(used - used / 2 - used / 4)
    vm.free_count = free
    return vm
}

@Test func memoryCountsAppWiredAndCompressedPages() {
    #expect(abs(memoryInUse(pages(inUse: 50)) - 50) < 0.001)
    #expect(abs(memoryInUse(pages(inUse: 80)) - 80) < 0.001)
}

@Test func memoryLeavesOutPurgeableAndFreePages() {
    #expect(abs(memoryInUse(pages(inUse: 50, purgeable: 10_000, free: 50_000)) - 50) < 0.001)
}

@Test func memoryDoesNotUnderflowWhenPurgeableExceedsInternal() {
    var vm = vm_statistics64()
    vm.internal_page_count = 100
    vm.purgeable_count = 500
    vm.wire_count = 1_000
    vm.compressor_page_count = 0
    #expect(memoryInUse(vm) >= 0)
}

@Test func cpuIsTheShareOfNewTicksSpentBusy() {
    var reading = CPUReading()
    reading.take((300, 100, 500, 100))   // since start-up: user, system, idle, nice
    #expect(reading.cpu == 50)
    reading.take((330, 110, 560, 100))   // 40 of the 100 new ticks busy
    #expect(reading.cpu == 40)
    reading.take((330, 110, 660, 100))   // 100 new ticks, all idle
    #expect(reading.cpu == 0)
}

@Test func cpuWaitsForFiftyNewTicks() {
    var reading = CPUReading()
    reading.take((300, 100, 500, 100))
    reading.take((340, 100, 500, 100))   // 40 new ticks: too few, the reading stays
    #expect(reading.cpu == 50)
    reading.take((360, 100, 500, 100))   // 60 since the last reading taken, all busy
    #expect(reading.cpu == 100)
}

@Test func smcKeysGoAsFourLettersInTheMacsByteOrder() {
    let request = SMC.request("Tp01", command: 5)
    #expect(Array(request[0..<4]) == [0x31, 0x30, 0x70, 0x54])   // "Tp01" is 0x54703031, lowest byte first
    #expect(request[28] == 4 && request[42] == 5)   // four bytes, read
    #expect(request.enumerated().allSatisfy { [0, 1, 2, 3, 28, 42].contains($0.offset) || $0.element == 0 })
    #expect(Array(SMC.request("F0Ac", command: 5)[0..<4]) == Array("cA0F".utf8))
}

@Test func askingForAKeysTypeAsksForNoBytes() {
    let request = SMC.request("Tp01", command: 9)
    #expect(Array(request[0..<4]) == [0x31, 0x30, 0x70, 0x54] && request[42] == 9)
    #expect(request.enumerated().allSatisfy { [0, 1, 2, 3, 42].contains($0.offset) || $0.element == 0 })
}

/// The SMC's answer to command 9: the key's size and type, and 0 for "found" (a key it does not have gets 132).
func keyInfo(size: UInt32, type: String, result: UInt8 = 0) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: 80)
    withUnsafeBytes(of: size) { output.replaceSubrange(28..<32, with: $0) }
    withUnsafeBytes(of: type.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) { output.replaceSubrange(32..<36, with: $0) }
    output[40] = result
    return output
}

@Test func onlyFourByteFloatsAreRead() {
    #expect(SMC.isFloat(keyInfo(size: 4, type: "flt ")))   // every temperature key on this M1 Pro
    #expect(!SMC.isFloat(keyInfo(size: 2, type: "sp78")))   // an Intel Mac's temperatures
    #expect(!SMC.isFloat(keyInfo(size: 2, type: "fpe2")))   // an Intel Mac's fans
    #expect(!SMC.isFloat(keyInfo(size: 4, type: "ui32")))
    #expect(!SMC.isFloat(keyInfo(size: 8, type: "flt ")))
    #expect(!SMC.isFloat(keyInfo(size: 4, type: "flt ", result: 132)))   // a key this Mac does not have
    #expect(!SMC.isFloat(nil))   // no SMC to ask
}

@Test func smcValuesAreFloatsAtByte48() {
    var output = [UInt8](repeating: 0, count: 80)
    withUnsafeBytes(of: Float32(42.5)) { output.replaceSubrange(48..<52, with: $0) }
    #expect(SMC.value(output) == 42.5)
    output[40] = 132
    #expect(SMC.value(output) == nil)   // no value is no reading, never 0
    #expect(SMC.value(nil) == nil)
}

@Test func eachChipGenerationHasItsOwnTemperatureKeys() {
    #expect(SMC.tempKeys["M1"] == ["Tp01", "Tp05", "Tp0L", "Tp0P"])   // the four TEMP has always read, checked on an M1 Pro
    #expect(Set(SMC.tempKeys.keys) == ["M1", "M2", "M3", "M4", "M5", "M6", "A18"])
    for (family, keys) in SMC.tempKeys {
        #expect((1...4).contains(keys.count), "\(family)")   // four reads at most, four times a second
        #expect(keys.allSatisfy { $0.utf8.count == 4 && $0.hasPrefix("T") }, "\(family)")
        #expect(Set(keys).count == keys.count, "\(family)")
        #expect(Hardware.family(of: "Apple \(family) Pro") == family, "\(family)")   // the chip's name leads to them
    }
    // A chip the table does not know yet has no keys, so TEMP is hidden rather than wrong.
    #expect(SMC.tempKeys[Hardware.family(of: "Apple M9") ?? ""] == nil)
    #expect(SMC.tempKeys[Hardware.family(of: "Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz") ?? ""] == nil)
}
