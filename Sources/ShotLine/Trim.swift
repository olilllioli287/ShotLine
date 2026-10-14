import AppKit
import AVKit
import Combine

/// Trims a screen recording in place, with the same trimming bar QuickTime
/// shows. It is to recordings what Markup is to screenshots: press and hold,
/// edit, and the result is written over the original file.
@MainActor
final class Trim: NSObject, NSWindowDelegate {
    static let shared = Trim()

    /// Called with the file once the trimmed recording has replaced it.
    var onSaved: (URL) -> Void = { _ in }
    /// Called once the window is up, still invisible, with the area the
    /// recording fills on screen. `show()` brings it in.
    var onShown: (URL, CGRect) -> Void = { _, _ in }
    /// Called with the file once the trimming window has closed, and where
    /// the recording was on screen.
    var onEnded: (URL, CGRect?) -> Void = { _, _ in }

    /// Brings in the window once the recording has flown into place.
    func show() {
        guard let window, window.alphaValue < 1 else { return }
        window.animator().alphaValue = 1
    }

    private var videoArea: CGRect? {
        window.map { $0.convertToScreen($0.contentLayoutRect) }
    }

    private var window: NSWindow?
    private var editing: URL?
    private var ready: AnyCancellable?

    /// Whether this recording is open for trimming right now, so it stays put.
    func isEditing(_ url: URL) -> Bool {
        window != nil && editing?.standardizedFileURL == url.standardizedFileURL
    }

    func edit(_ url: URL, size: CGSize) {
        window?.close()

        let item = AVPlayerItem(url: url)
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(playerItem: item)
        playerView.controlsStyle = .inline

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.windowSize(for: size)),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.contentView = playerView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        editing = url
        NSApp.activate(ignoringOtherApps: true)
        // The recording flies in first; the window waits invisible for it.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        if let area = videoArea { onShown(url, area) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.show() }

        // The trimming bar can only come up once the recording has loaded.
        ready = item.publisher(for: \.status)
            .first { $0 != .unknown }
            .receive(on: RunLoop.main)
            .sink { [weak self, weak playerView] status in
                guard let self, let playerView, status == .readyToPlay, playerView.canBeginTrimming else {
                    log.error("Could not trim \(url.lastPathComponent, privacy: .public)")
                    return
                }
                playerView.beginTrimming { result in
                    DispatchQueue.main.async {
                        if result == .okButton { self.save(item, to: url) }
                        self.window?.close()
                    }
                }
            }
    }

    /// The recording at its own proportions, as large as fits comfortably.
    private static func windowSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 720, height: 450) }
        let scale = min(720 / size.width, 520 / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        let area = videoArea
        (window?.contentView as? AVPlayerView)?.player?.pause()
        ready = nil
        window = nil
        if let editing { onEnded(editing, area) }
    }

    // MARK: Writing back

    /// Copies the kept part without re-encoding, to a hidden file next to the
    /// original so the watcher ignores it, then swaps it in.
    private func save(_ item: AVPlayerItem, to target: URL) {
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
        guard let export = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetPassthrough) else {
            NSSound.beep()
            return
        }
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".trimming-\(UUID().uuidString)")
            .appendingPathExtension(target.pathExtension)
        export.outputURL = temp
        export.outputFileType = target.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        export.timeRange = CMTimeRange(start: start, end: end)
        Task {
            await export.export()
            if export.status == .completed,
               (try? FileManager.default.replaceItemAt(target, withItemAt: temp)) != nil {
                log.notice("Trimmed \(target.lastPathComponent, privacy: .public)")
                onSaved(target)
            } else {
                log.error("Could not trim \(target.lastPathComponent, privacy: .public): \(export.error?.localizedDescription ?? "", privacy: .public)")
                try? FileManager.default.removeItem(at: temp)
                NSSound.beep()
            }
        }
    }
}
