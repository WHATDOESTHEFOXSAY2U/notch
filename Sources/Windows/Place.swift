import AppKit

/// Where a swipe can send a window. Each place is a rectangle inside a screen one unit wide and one
/// unit tall, measured from the top left; minimising has no rectangle of its own, only a picture.
/// Two more are not places at all: `full` is the Mac's own full screen, and `close` closes the window.
enum Place {
    case left, right, fill, minimize, topLeft, topRight, lowLeft, lowRight, full, close

    /// The part of the screen the window takes, and the part of the small picture that lights up.
    var unit: CGRect {
        switch self {
        case .left: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .fill, .full, .close: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .minimize: CGRect(x: 5.0 / 23, y: 10.0 / 14, width: 13.0 / 23, height: 4.0 / 14)   // a bar at the bottom edge: the Dock
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .lowLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .lowRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        }
    }

    /// What the picture lights up in. Everything that only moves the window is white. The three things the
    /// window's own buttons do take those buttons' colours: green for full screen, yellow to minimise, red to close.
    var color: NSColor {
        switch self {
        case .full: .systemGreen
        case .minimize: .systemYellow
        case .close: .systemRed
        default: .white
        }
    }

    /// Full screen and closing take over the whole picture, edge included, so they cannot be mistaken for filling the screen.
    var whole: Bool { self == .full || self == .close }
}
