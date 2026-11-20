import SwiftUI
import AVFoundation

/// Live camera picture, flipped like a mirror. The camera runs from the moment this view is made until `stop`.
final class Camera: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notch.camera")   // starting and stopping block, so they happen here, in order
    private var stopped = false

    init() {
        super.init(frame: .zero)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer = preview
        wantsLayer = true

        // The first use shows the macOS camera prompt.
        AVCaptureDevice.requestAccess(for: .video) { [self] allowed in
            queue.async { [self] in
                // Not allowed, switched off again before it came on, or no camera: nothing to show, and nothing failed.
                guard allowed, !stopped, let camera = AVCaptureDevice.default(for: .video) else { return }
                do { session.addInput(try AVCaptureDeviceInput(device: camera)) }
                catch { return Log.failed(.panel, "the camera would not open", error: error) }
                session.startRunning()
                if !session.isRunning { Log.failed(.panel, "the camera would not start") }
                DispatchQueue.main.async {
                    preview.connection?.automaticallyAdjustsVideoMirroring = false
                    preview.connection?.isVideoMirrored = true
                }
            }
        }
    }
    required init?(coder _: NSCoder) { nil }

    func stop() {
        queue.async { [self] in
            stopped = true
            session.stopRunning()
        }
    }
}

/// The camera as a part of the panel. It runs only while this view is on screen.
struct Mirror: NSViewRepresentable {
    func makeNSView(context: Context) -> Camera { Camera() }
    func updateNSView(_: Camera, context: Context) {}
    static func dismantleNSView(_ camera: Camera, coordinator: ()) { camera.stop() }
}
