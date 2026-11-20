import AppKit

if CommandLine.arguments.last == "warm" {   // the short-lived Notch described in Launch.swift: read once and leave
    warmReader()
    exit(0)
}
// One copy at a time. A second copy (the same app in another folder, say) opens the first one, which then shows its
// Settings, and quits before it starts anything: no taps, no change to Caps Lock or the sound. The warm helper above is
// a second Notch on purpose, so it leaves before this check.
if let first = Launch.otherCopy() {
    if let folder = first.bundleURL { NSWorkspace.shared.open(folder) }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
