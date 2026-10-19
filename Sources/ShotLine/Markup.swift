import AppKit
import UniformTypeIdentifiers

/// Opens a screenshot in the system Markup editor, the window macOS shows
/// when you click the thumbnail of a screenshot you just took. It is a
/// system extension, reached through the sharing service it registers.
@MainActor
final class Markup: NSObject, NSSharingServiceDelegate {
    static let shared = Markup()

    /// Called with the file once the edited image has been written back.
    var onSaved: (URL) -> Void = { _ in }
    /// Called once Markup is in place, still invisible, with the area its
    /// image fills on screen. `show()` brings it in.
    var onShown: (URL, CGRect) -> Void = { _, _ in }
    /// Called the moment Markup starts to close, with Done or Escape, with
    /// where its image was. Any edit is written back a little later.
    var onClosing: (URL, CGRect) -> Void = { _, _ in }
    /// Called with the file once Markup has closed, after any edit has been
    /// written back, and where its image was if `onClosing` never came.
    var onEnded: (URL, CGRect?) -> Void = { _, _ in }

    /// The height of Markup's toolbar, above the image.
    private static let toolbarHeight: CGFloat = 48
    /// Markup's windows while they wait invisible for the photo.
    private var hidden: [NSWindow] = []
    /// Where Markup's image sits on screen.
    private var imageArea: CGRect?
    /// The editor itself, watched for the moment it starts to close.
    private weak var editor: NSWindow?
    private var closeWatch: Timer?
    private var reportedClosing = false

    private var editing: URL?
    private static let serviceName = NSSharingService.Name("com.apple.MarkupUI.Markup")

    /// Returns false when Markup could not open and Preview opened the file
    /// instead; then no end is reported.
    @discardableResult
    func edit(_ url: URL) -> Bool {
        guard let service = NSSharingService(named: Markup.serviceName),
              service.canPerform(withItems: [url]) else {
            // Without the extension, Preview is the closest thing.
            NSWorkspace.shared.open(url)
            return false
        }
        editing = url
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        service.perform(withItems: [url])
        centerNewWindow(excluding: before, screen: NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
        return true
    }

    /// Markup opens wherever the system puts it, often half off the screen.
    /// Its windows belong to this app, so once they show up they are moved to
    /// the middle of the screen the photo was clicked on. It may still change
    /// size as the image loads, so it is centred a few more times after that.
    private func centerNewWindow(excluding before: Set<ObjectIdentifier>, screen: NSScreen?,
                                 waited: Int = 0, settled: Int = 0) {
        guard waited < 40, settled < 10, editing != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (settled == 0 ? 0.02 : 0.05)) { [weak self] in
            guard let self else { return }
            // Markup lays windows over the whole screen for its blur, shadow
            // and clicks outside, and puts its own on top. Only the one smaller
            // than the screen is the editor; the blur and shadow are drawn
            // around where it first opened, so they move by the same distance.
            let added = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
            let window = added.first { $0.frame.width < ($0.screen?.frame.width ?? .infinity) }
            if let window { self.editor = window }
            guard let window, let area = (screen ?? window.screen ?? NSScreen.main)?.visibleFrame else {
                self.centerNewWindow(excluding: before, screen: screen, waited: waited + 1)
                return
            }
            // The photo flies in first; Markup stays invisible till it lands.
            let first = settled == 0
            if first {
                for w in added { w.alphaValue = 0 }
                self.hidden = added
            }
            let size = window.frame.size
            let dx = (area.midX - size.width / 2).rounded() - window.frame.minX
            let dy = (area.midY - size.height / 2).rounded() - window.frame.minY
            if dx != 0 || dy != 0 {
                // They hang off one clear window that covers the screen, and
                // move with it. Moving only the ones hanging off it keeps that
                // one covering the screen.
                let children = added.filter { w in added.contains { $0 === w.parent } }
                for w in children.isEmpty ? added : children {
                    w.setFrameOrigin(NSPoint(x: w.frame.minX + dx, y: w.frame.minY + dy))
                }
            }
            var image = window.frame
            image.size.height -= Self.toolbarHeight
            self.imageArea = image
            if first, let url = self.editing {
                self.onShown(url, image)
                // Never left invisible, whatever happens to the flight.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.show() }
            }
            self.centerNewWindow(excluding: before, screen: screen, waited: waited, settled: settled + 1)
        }
    }

    /// Brings in Markup once the photo has flown into place.
    func show() {
        let windows = hidden
        hidden = []
        guard !windows.isEmpty else { return }
        // The editor appears at once under the photo that flew in; the blur
        // and shadow around it fade in.
        editor?.alphaValue = 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            for w in windows where w !== editor { w.animator().alphaValue = 1 }
        }
        watchForClose()
    }

    /// Done and Escape first make the editor vanish, then fade the blur for a
    /// third of a second, and only then tell the delegate. The photo flies
    /// back as soon as the editor vanishes, so it moves while the blur fades.
    private func watchForClose() {
        closeWatch?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let editor = self.editor, editor.isVisible, editor.alphaValue > 0.5 { return }
                self.closeWatch?.invalidate()
                self.closeWatch = nil
                self.reportClosing()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        closeWatch = timer
    }

    private func reportClosing() {
        FocusReturn.shared.scheduleCheck()
        guard !reportedClosing, let url = editing, let area = imageArea else { return }
        reportedClosing = true
        onClosing(url, area)
    }

    private func end(_ target: URL) {
        closeWatch?.invalidate()
        closeWatch = nil
        let area = reportedClosing ? nil : imageArea
        imageArea = nil
        reportedClosing = false
        show()
        onEnded(target, area)
    }

    /// Whether Markup is open on any file.
    var isOpen: Bool { editing != nil }

    /// Whether any of Markup's windows is still on screen or about to come
    /// in. Escape closes the editor without telling the delegate, so
    /// `isOpen` can stay true after it is gone.
    var isOnScreen: Bool {
        if !hidden.isEmpty { return true }
        guard let editor else { return false }
        return editor.isVisible && editor.alphaValue > 0.05
    }

    /// Whether this file is open in Markup right now, so it stays put.
    func isEditing(_ url: URL) -> Bool {
        editing?.standardizedFileURL == url.standardizedFileURL
    }

    // MARK: NSSharingServiceDelegate

    /// Done was pressed. The extension hands back the edited image and the
    /// host app is the one that writes it over the original file.
    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { self.save(items) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService,
                                    didFailToShareItems items: [Any], error: Error) {
        MainActor.assumeIsolated {
            if let target = self.editing { self.end(target) }
            self.editing = nil
        }
        log.notice("Markup ended without saving: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: Writing back

    private func save(_ items: [Any]) {
        guard let target = editing else { return }
        editing = nil
        guard let item = items.first else {
            end(target)
            return
        }
        log.notice("Markup returned \(String(describing: type(of: item)), privacy: .public)")

        switch item {
        case let url as URL:
            write(from: url, to: target)
        case let image as NSImage:
            write(data: pngData(image), to: target)
        case let provider as NSItemProvider:
            load(provider, into: target)
        default:
            log.error("Markup returned an unexpected item")
            end(target)
        }
    }

    private func load(_ provider: NSItemProvider, into target: URL) {
        let types = provider.registeredTypeIdentifiers
        log.notice("Markup provider types: \(types.joined(separator: ", "), privacy: .public)")

        if types.contains(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { self.write(from: url, to: target) } else { self.end(target) }
                }
            }
            return
        }
        // Prefer the original format, then any image format.
        let original = UTType(filenameExtension: target.pathExtension)?.identifier
        let imageType = types.first { $0 == original }
            ?? types.first { UTType($0)?.conforms(to: .image) == true }
        guard let imageType else {
            end(target)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
            DispatchQueue.main.async { self.write(data: data, to: target) }
        }
    }

    private func write(from source: URL, to target: URL) {
        if source.standardizedFileURL == target.standardizedFileURL {
            onSaved(target)
            end(target)
        } else {
            write(data: try? Data(contentsOf: source), to: target)
        }
    }

    private func write(data: Data?, to target: URL) {
        defer { end(target) }
        guard let data else { return }
        do {
            try data.write(to: target, options: .atomic)
            onSaved(target)
        } catch {
            log.error("Could not save markup: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
