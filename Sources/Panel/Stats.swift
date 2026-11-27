import AppKit
import IOKit.ps

/// Live system readings: four times a second while the panel is open, every 2 seconds while closed.
@Observable final class Stats {
    var mem = 0.0        // percent of RAM in use
    var cpu = 0.0        // percent, all cores
    var temp: Double?    // °C, hottest CPU sensor; nil when no sensor answers, and TEMP is then hidden, never 0
    var fan = 0.0        // rpm, fastest fan (0 when idle)
    var swap = 0.0       // GB
    var battery: Double? // percent; nil on a Mac without one
    var charging = false // on mains power
    var pressure = 1     // kernel memory pressure: 1 normal, 2 warning, 4 critical
    var apps: [(app: NSRunningApplication, gb: Double)] = []
    var open = false { didSet { openTick = 0; if open { refresh(); look() } else { quitting = []; owners = [:] }; schedule() } }
    /// The parts the panel cannot show on this Mac right now, by their names in `Parts`: TEMP without a sensor that
    /// answers, DICT without a microphone or Apple's speech engine, SCRIBE (TRANSCRIBE) without the Scribe app,
    /// CAM (the mirror) without a camera.
    var missing: Set<String> { temp == nil ? lacking.union(["TEMP"]) : lacking }

    private var lacking: Set<String> = []   // the tools whose hardware `look` found missing
    private var lastTicks = (busy: 0.0, total: 0.0)
    private var quitting: Set<pid_t> = []   // apps asked to quit; hidden from the list right away
    private var owners: [pid_t: pid_t] = [:]   // which app each process belongs to; looked up once per process
    private var openTick = 0
    private var timer: Timer?

    init() {
        refresh()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: open ? 0.25 : 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        // Memory, counted the way Activity Monitor does: app + wired + compressed.
        let vm = host(HOST_VM_INFO64, vm_statistics64())
        let pages = (vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) + vm.wire_count + vm.compressor_page_count
        mem = Double(pages) * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100
        pressure = Int(sysctl("kern.memorystatus_vm_pressure_level", Int32(1)))
        swap = Double(sysctl("vm.swapusage", xsw_usage()).xsu_used) / 1e9

        // CPU: share of ticks spent busy since the last reading. Too few new ticks would be noise, so wait.
        let t = host(HOST_CPU_LOAD_INFO, host_cpu_load_info()).cpu_ticks   // user, system, idle, nice
        let busy = Double(t.0) + Double(t.1) + Double(t.3), total = busy + Double(t.2)
        if total - lastTicks.total >= 50 {
            cpu = (busy - lastTicks.busy) / (total - lastTicks.total) * 100
            lastTicks = (busy, total)
        }

        temp = SMC.found.compactMap(SMC.shared.read).max()

        // Battery: the first power source that reports a capacity.
        let power = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        for source in IOPSCopyPowerSourcesList(power).takeRetainedValue() as [CFTypeRef] {
            guard let info = IOPSGetPowerSourceDescription(power, source)?.takeUnretainedValue() as? [String: Any],
                  let now = info[kIOPSCurrentCapacityKey] as? Double,
                  let full = info[kIOPSMaxCapacityKey] as? Double, full > 0 else { continue }
            battery = now / full * 100
            charging = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            break
        }

        // Fans and apps are only visible while the panel is open; walk all processes once a second rather than 4x/sec.
        if open {
            fan = SMC.fans.compactMap(SMC.shared.read).max() ?? 0
            if openTick % 4 == 0 { apps = topApps() }
            openTick += 1
        }
    }

    /// Looks, as the panel opens, for what DICT and the mirror need: a microphone and Apple's speech engine, and a
    /// camera. TRANSCRIBE stays visible in the bar even before Scribe is installed so every Mac discovers it and sees
    /// what is needed when pressed. Away from the main thread, since the first microphone look takes ~0.1 s.
    private func look() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lacking: Set<String> = []
            if !Hardware.hasMicrophone || !Hardware.canDictate { lacking.insert("DICT") }
            if !Hardware.hasCamera { lacking.insert("CAM") }
            DispatchQueue.main.async { self?.lacking = lacking }
        }
    }

    /// Force-quits an app and drops it from the list at once. Instant, but the app gets no chance to save.
    func quit(_ app: NSRunningApplication) {
        app.forceTerminate()
        quitting.insert(app.processIdentifier)
        apps = topApps()
    }

    /// The four apps using the most memory, helper processes included.
    private func topApps() -> [(app: NSRunningApplication, gb: Double)] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * 4)))
        var bytes: [pid_t: UInt64] = [:]   // memory per owning app
        var usage = rusage_info_v4()
        for pid in pids.prefix(max(count, 0)) {
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0
            guard ok else { continue }
            let app = owners[pid] ?? PrivateCalls.owner(of: pid)
            owners[pid] = app
            bytes[app, default: 0] += usage.ri_phys_footprint
        }
        let ranked: [(app: NSRunningApplication, gb: Double)] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !quitting.contains($0.processIdentifier) }
            .map { (app: $0, gb: Double(bytes[$0.processIdentifier] ?? 0) / 1e9) }
        return Array(ranked.sorted { $0.gb > $1.gb }.prefix(4))
    }
}

/// Reads one kernel statistics struct (memory or CPU counters).
private func host<T>(_ flavor: Int32, _ empty: T) -> T {
    var value = empty
    var count = mach_msg_type_number_t(MemoryLayout<T>.size / MemoryLayout<integer_t>.size)
    withUnsafeMutablePointer(to: &value) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            _ = host_statistics64(mach_host_self(), flavor, $0, &count)
        }
    }
    return value
}

/// Reads one sysctl value by name.
private func sysctl<T>(_ name: String, _ empty: T) -> T {
    var value = empty
    var size = MemoryLayout<T>.size
    withUnsafeMutablePointer(to: &value) { _ = sysctlbyname(name, $0, &size, nil, 0) }
    return value
}
