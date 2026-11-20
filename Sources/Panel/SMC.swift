import IOKit

/// Apple's System Management Controller: the chip that knows temperatures and fan speeds. It answers to four-letter
/// keys, like "Tp01". Apple documents neither the keys nor what each holds, and both change from one chip to the next.
struct SMC {
    /// The keys TEMP tries, by chip generation (`Hardware.chipFamily`): up to four sensors on the chip's fastest cores,
    /// which run hottest. Each read costs about 0.2 ms, and the other core sensors stay within a few degrees of these.
    /// Taken from the list in the Stats app (github.com/exelban/stats, MIT licence, Modules/Sensors/values.swift at
    /// commit a04bc5e629242c9a29a98ef32ed1f5f46a88c874). Only M1's were tried, on an M1 Pro. A chip not here has no
    /// TEMP until its keys are added.
    static let tempKeys = [
        "M1": ["Tp01", "Tp05", "Tp0L", "Tp0P"],
        "M2": ["Tp01", "Tp05", "Tp09", "Tp0D"],
        "M3": ["Tf04", "Tf09", "Tf0A", "Tf0B"],
        "M4": ["Tp01", "Tp05", "Tp09", "Tp0D"],
        "M5": ["Tp00", "Tp04", "Tp08", "Tp0C"],
        "M6": ["Tp0j", "Tp0g", "Tp09", "Tp07"],
        "A18": ["Tp05", "Tp0D"],   // the MacBook Neo
    ]
    /// The fans' speeds, in turns a minute. A Mac without fans has neither key.
    static let fanKeys = ["F0Ac", "F1Ac"]

    /// The one connection to the SMC, opened at the first reading and kept.
    static let shared = SMC()
    /// The keys TEMP reads on this Mac: those of its chip that the SMC holds as numbers TEMP can read. Asked once.
    /// None when the chip is not in the table or the SMC would not open, and TEMP is then hidden.
    static let found = (tempKeys[Hardware.chipFamily ?? ""] ?? []).filter(shared.readable)
    /// The fan keys this Mac has, asked once in the same way.
    static let fans = fanKeys.filter(shared.readable)

    private var connection: io_connect_t = 0

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if opened != KERN_SUCCESS { Log.failed(.panel, "the SMC would not open", code: Int(opened)) }
    }

    /// The value of a key that `readable` let through, or nil if the SMC gave none this time.
    func read(_ key: String) -> Double? { SMC.value(call(SMC.request(key, command: 5))) }

    /// Whether the SMC has `key`, as a number TEMP can read: a 4-byte float. It is asked for the key's size and type.
    func readable(_ key: String) -> Bool { SMC.isFloat(call(SMC.request(key, command: 9))) }

    /// One call, one 80-byte block each way. Nil if the call itself failed.
    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 80), size = 80
        return IOConnectCallStructMethod(connection, 2, input, 80, &output, &size) == kIOReturnSuccess ? output : nil
    }

    // The blocks, apart from the SMC, so they can be tested.
    // Offsets: 0 key · 28 data size · 32 data type · 40 result · 42 command · 48 data

    /// The block that asks about `key`: command 5 reads its value, command 9 its size and type.
    static func request(_ key: String, command: UInt8) -> [UInt8] {
        var input = [UInt8](repeating: 0, count: 80)
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        withUnsafeBytes(of: code) { input.replaceSubrange(0..<4, with: $0) }
        if command == 5 { input[28] = 4 }   // a read says how many bytes it wants: every value read here is a 4-byte float
        input[42] = command
        return input
    }

    /// Whether the answer to command 9 says the key holds a 4-byte float ("flt "). A key the SMC does not have
    /// answers with a result other than 0.
    static func isFloat(_ output: [UInt8]?) -> Bool {
        guard let output, output[40] == 0 else { return false }
        let size = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) }
        let type = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
        return size == 4 && type == 0x666C_7420   // "flt ", its four letters as one number
    }

    /// The value in the answer to command 5: a float at byte 48. Nil when the SMC gave none.
    static func value(_ output: [UInt8]?) -> Double? {
        guard let output, output[40] == 0 else { return nil }
        return Double(output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 48, as: Float32.self) })
    }
}
