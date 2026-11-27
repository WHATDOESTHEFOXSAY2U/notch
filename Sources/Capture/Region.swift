import AppKit
import ScreenCaptureKit

/// A rectangle on one screen, in points measured from that screen's top-left corner.
struct Region {
    let rect: CGRect
    let screen: NSScreen

    /// What the system needs to look at this rectangle: the screen without Notch's own windows
    /// (so the panel and the selection overlay never show up), at the screen's full pixel resolution.
    /// `keeping` lists the Notch windows that should be in the picture after all (their `windowNumber`),
    /// like a recording's click marks. They must be on screen before `content` is fetched.
    func source(in content: SCShareableContent, keeping: [Int] = []) throws -> (filter: SCContentFilter, config: SCStreamConfiguration) {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CocoaError(.featureUnsupported) }
        let me = content.applications.filter { $0.processID == getpid() }
        let kept = content.windows.filter { keeping.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: kept)
        let scale = CGFloat(filter.pointPixelScale)   // 2 on the built-in display
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = max(2, Int(rect.width * scale))
        config.height = max(2, Int(rect.height * scale))
        return (filter, config)
    }

    /// A still picture of the rectangle, without the pointer.
    func picture(in content: SCShareableContent) async throws -> CGImage {
        let (filter, config) = try source(in: content)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// The picture as PNG file data. `scale` is pixels per point, stored in the file so a Retina
/// picture opens at the size it had on screen instead of twice as big.
func png(_ image: CGImage, scale: CGFloat) -> Data? {
    let data = NSMutableData()
    guard let file = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(file, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    return CGImageDestinationFinalize(file) ? data as Data : nil
}
