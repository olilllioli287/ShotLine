import AppKit

/// Hands the keyboard back to the app you were in once ShotLine is done with
/// it.
///
/// ShotLine comes to the front for Markup, Quick Look, Trim, the shortcut
/// window, the guide and its alerts. When the last of those closes, macOS is
/// left to pick the next app on its own, and an input method can miss that
/// the app you were typing in is back: vChewing then keeps a stale session
/// and Shift no longer switches between Chinese and English there
/// (vChewing issue #618). Bringing that app back explicitly gives the input
/// method a clean activation.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()

    /// The last app other than ShotLine that was in front.
    /// Held strongly: the object from the notification is not kept anywhere
    /// else, so a weak reference would be gone at once.
    private var previous: NSRunningApplication?
    private var check: DispatchWorkItem?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app != .current { FocusReturn.shared.previous = app }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previous = front }
        // A window of ours closing or giving up the keyboard may leave
        // ShotLine in front with nothing to type into.
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FocusReturn.shared.scheduleCheck() }
            }
        }
    }

    /// Markup fades its blur after the editor goes, so this looks again a few
    /// times before deciding.
    func scheduleCheck(attempt: Int = 0) {
        check?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.giveBackIfIdle(attempt: attempt) }
        }
        check = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func giveBackIfIdle(attempt: Int) {
        guard NSApp.isActive else { return }
        if hasWindowInUse {
            // Something of ours is still open (or still fading out).
            if attempt < 8 { scheduleCheck(attempt: attempt + 1) }
            return
        }
        guard let app = previous, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
        log.notice("Gave the keyboard back to \(app.bundleIdentifier ?? "?", privacy: .public)")
    }

    /// A visible window that can take the keyboard, other than the line and
    /// the capture animation, which never activate the app.
    private var hasWindowInUse: Bool {
        if QuickLook.shared.isVisible || Markup.shared.isOnScreen { return true }
        if NSApp.modalWindow != nil { return true }
        return NSApp.windows.contains { w in
            w.isVisible && w.alphaValue > 0.05 && w.canBecomeKey && !w.styleMask.contains(.nonactivatingPanel)
        }
    }
}
