import Foundation
import Testing
@testable import Logic

// AppInfo.swift: the line at the bottom of Settings, and where the app runs from. While the app runs, these come from
// Info.plist and from macOS; here they are given.

@Test func theVersionLineIsTheNameInCapitalsTheVersionAndTheBuild() {
    #expect(AppInfo.versionLine(name: "Notch", version: "0.9.0", build: "123") == "NOTCH 0.9.0 (123)")
    #expect(AppInfo.versionLine(name: "Two Words", version: "1.0.0", build: "7") == "TWO WORDS 1.0.0 (7)")
}

@Test func onlyAnApplicationsFolderCounts() {
    let home = NSHomeDirectory()
    let folders = ["/Applications", home + "/Applications", "/Network/Applications", "/System/Applications"]   // as macOS lists them
    #expect(AppInfo.isInApplications("/Applications/Notch.app", folders: folders))
    #expect(AppInfo.isInApplications("/Applications/Utilities/Notch.app", folders: folders))
    #expect(AppInfo.isInApplications(home + "/Applications/Notch.app", folders: folders))
    #expect(!AppInfo.isInApplications(home + "/Downloads/Notch.app", folders: folders))
    #expect(!AppInfo.isInApplications("/Volumes/Notch/Notch.app", folders: folders))   // still on the disk image
    #expect(!AppInfo.isInApplications(home + "/Projects/Notch/Notch.app", folders: folders))   // built with build.sh
    #expect(!AppInfo.isInApplications("/private/var/folders/x/T/AppTranslocation/1A2B/d/Notch.app", folders: folders))
    #expect(!AppInfo.isInApplications("/Applications Old/Notch.app", folders: folders))
}
