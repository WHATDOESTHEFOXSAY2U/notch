import CoreGraphics
import Foundation

/// The windows on screen, as the window server lists them, front to back. No app is asked anything.
enum WindowList {
    /// One window in the list.
    struct Entry {
        let layer: Int             // 0 for ordinary windows; menus, the Dock and floating panels lie on higher layers
        let app: pid_t             // the app it belongs to
        let owner: String          // the owning process's name, to filter out system UI windows
        let number: CGWindowID     // the window server's own number for it
        let frame: CGRect          // measured from the top left of the main screen
        let seen: Bool             // it is drawn at all: one that is fully see-through (alpha 0) is not
    }

    /// The windows on screen now, front to back, without the desktop's own.
    static func read() -> [Entry] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []).map {
            Entry(layer: $0[kCGWindowLayer] as? Int ?? 0, app: $0[kCGWindowOwnerPID] as? pid_t ?? 0,
                  owner: $0[kCGWindowOwnerName] as? String ?? "",
                  number: $0[kCGWindowNumber] as? CGWindowID ?? 0,
                  frame: ($0[kCGWindowBounds] as? NSDictionary).flatMap(CGRect.init(dictionaryRepresentation:)) ?? .zero, seen: ($0[kCGWindowAlpha] as? Double ?? 1) > 0)
        }
    }
}

extension Windows {
    /// The numbers of `app`'s windows on screen now, from the window server; the app itself is asked nothing.
    static func onScreen(_ app: pid_t) -> [CGWindowID] {
        WindowList.read().filter { $0.app == app }.map(\.number)
    }
}
