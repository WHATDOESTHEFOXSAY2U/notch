import ServiceManagement

/// START AT LOGIN, in Settings and on the welcome card: macOS opens the app when you log in. Only a copy in an
/// Applications folder can have it, since one in Downloads or on a disk image may move or go. Switching it off works
/// from anywhere.
enum LoginItem {
    /// Whether macOS opens the app at login now.
    static var on: Bool { SMAppService.mainApp.status == .enabled }

    /// Switches it on or off, and says whether it is on afterwards. A copy outside Applications is never added.
    static func set(_ on: Bool) -> Bool {
        if !on || AppInfo.inApplications {
            do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
            catch { Log.failed(.settings, "macOS refused to change the login item", error: error) }
        }
        return self.on
    }
}
