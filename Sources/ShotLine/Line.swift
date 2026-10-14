import AppKit
import AVFoundation
import Combine
import os

let log = Logger(subsystem: "local.shotline.ShotLine", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// When the file was last saved, to notice an edit made in another app.
    var modified: Date? = nil
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// Taken off the line while it is open in Markup or the trimming
    /// window. It hangs again when the editor closes.
    var away = false
    /// A screen recording rather than a screenshot.
    var isRecording: Bool { ShotLine.isRecording(url) }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying && a.away == b.away && a.thumb === b.thumb
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]

    var maxItems = 8
    /// How many photos fit across the screen. With Keep on line set, the
    /// line can hold more, and the rest are reached by scrolling.
    var visibleCount = 8
    /// How far the line is scrolled towards older photos, in points; 0 shows
    /// the newest.
    @Published var scroll: CGFloat = 0

    /// Keep on line, from the menu bar: how many photos the line keeps, or
    /// nil for as many as fit across the screen.
    nonisolated static let keepChoices = [25, 50, 100]
    nonisolated static var keepOnLine: Int? {
        get {
            let n = UserDefaults.standard.integer(forKey: "keepOnLine")
            return keepChoices.contains(n) ? n : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "keepOnLine") }
    }


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"

    init() {
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }), !justKept.contains(url.path),
              !wasHung(url), let thumb = makeThumbnail(url) else { return nil }
        if let file = fileID(url) { hungFiles.insert(file) }
        var item = Pegged(url: url, thumb: thumb, modified: modificationDate(url))
        item.flying = flying
        items.append(item)
        scroll = 0
        // A full line lets the oldest photo fall off the far end. Only one: a
        // line hung on a wider screen keeps its length here instead of losing
        // several photos to a single capture.
        if liveCount > maxItems, let oldest = items.first(where: { !$0.falling }) {
            letGo(oldest.id)
        }
        save()
        if !quietly { play("Tink", volume: 0.35) }
        if isInInbox(item.id) { scheduleKeep(item.id) }
        return item.id
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    /// Called when a photo was dragged into an app, so the line goes back up.
    var onSent: (() -> Void)?

    /// Called when an edited photo hangs again, so the line comes down to show
    /// it, with where the editor showed it when it should fly back.
    var onRehung: ((UUID, CGRect?) -> Void)?

    /// `falls: false` makes it vanish at once instead of falling off the screen.
    func drop(_ id: UUID, quietly: Bool = false, falls: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        if falls { onFall?(items[i]) }
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    /// "Take everything down": every photo goes the way of its corner cross.
    func clear() {
        takeDown(items.filter { !$0.falling })
    }

    /// The photos hung before (left) or after (right) this one.
    func neighbours(of id: UUID, toTheLeft: Bool) -> [Pegged] {
        let live = items.filter { !$0.falling }
        guard let i = live.firstIndex(where: { $0.id == id }) else { return [] }
        return toTheLeft ? Array(live[..<i]) : Array(live[(i + 1)...])
    }

    /// Takes down everything on one side of a photo. Each one goes the way
    /// of its own corner button: to the Trash from ShotLine's folder, and
    /// only off the line from anywhere else.
    func takeDown(_ id: UUID, toTheLeft: Bool) {
        takeDown(neighbours(of: id, toTheLeft: toTheLeft))
    }

    /// One after another, and only the first makes a sound.
    private func takeDown(_ live: [Pegged]) {
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.discard(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    /// Those saved again, like an edit in Preview, show the new version.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
        for i in items.indices where !items[i].falling {
            let modified = modificationDate(items[i].url)
            guard modified != items[i].modified, let thumb = makeThumbnail(items[i].url) else { continue }
            items[i].thumb = thumb
            items[i].modified = modified
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let entry = NSPasteboardItem()
        // A recording is copied as the file, which apps paste as the video.
        if !item.isRecording, let png = pngData(item.url) { entry.setData(png, forType: .png) }
        entry.setString(item.url.absoluteString, forType: .fileURL)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry])

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        held.insert(id)
        NSWorkspace.shared.open(item.url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    @discardableResult
    func trash(_ id: UUID, quietly: Bool = false) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            drop(id, quietly: true)
            return true
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !quietly { NSSound.beep() }
            return false
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in ShotLine's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID, quietly: Bool = false) {
        if isInInbox(id) { trash(id, quietly: quietly) } else { drop(id, quietly: quietly) }
    }

    /// Moves along a line that holds more than fit, from a scroll gesture.
    func scroll(by delta: CGFloat) {
        let most = CGFloat(max(0, items.count - visibleCount)) * Layout.spacing
        let next = min(most, max(0, scroll + delta))
        if next != scroll { scroll = next }
    }

    /// After Keep on line is lowered, the oldest photos past it go the way
    /// of a full line.
    func trim() {
        while liveCount > maxItems, let oldest = items.first(where: { !$0.falling }) {
            letGo(oldest.id)
        }
        scroll = 0
    }

    /// A capture in ShotLine's folder is kept rather than trashed, so a full
    /// line never throws away a screenshot, edited or not.
    private func letGo(_ id: UUID) {
        if isInInbox(id) { keep(id, quietly: true) }
        drop(id, quietly: true)
    }

    /// Inbox mode: keep a capture by moving it to the screenshots folder
    /// macOS used before. The corner checkmark does it at once, and every
    /// capture does it by itself `keepDelay` seconds after it was hung.
    func keep(_ id: UUID, quietly: Bool = false) {
        guard let item = items.first(where: { $0.id == id && !$0.falling }) else { return }
        if moveToKeepFolder(item.url) {
            drop(id, quietly: true)
        } else if !quietly {
            NSSound.beep()
        }
    }

    private func moveToKeepFolder(_ url: URL) -> Bool {
        let folder = Inbox.keepFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = uniqueURL(in: folder, for: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            log.notice("Kept \(url.lastPathComponent, privacy: .public) in \(folder.path, privacy: .public)")
            // A watcher on that folder, like the one on the Desktop, would
            // see it arrive and hang it all over again.
            let path = target.path
            justKept.insert(path)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.justKept.remove(path) }
            return true
        } catch {
            log.error("Could not keep \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Dragged into an app, which has its copy: the photo vanishes and the
    /// line goes back up at once. A capture's file moves on to the screenshots
    /// folder a moment later, once the app has read it. A photo being edited
    /// stays, as with the timer.
    func sent(_ id: UUID) {
        guard !held.contains(id), let item = items.first(where: { $0.id == id && !$0.falling }) else { return }
        let inInbox = isInInbox(id)
        drop(id, quietly: true, falls: false)
        onSent?()
        guard inInbox else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            _ = self?.moveToKeepFolder(item.url)
        }
    }

    /// Put away after, from the menu bar: seconds before a capture moves on
    /// by itself and the line goes back up, or nil for never.
    nonisolated static let keepDelayChoices: [TimeInterval] = [15, 30, 180]
    nonisolated static var keepDelay: TimeInterval? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "keepDelay") != nil else { return 15 }
            let n = defaults.double(forKey: "keepDelay")
            return keepDelayChoices.contains(n) ? n : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "keepDelay") }
    }

    /// The photo the pointer is over. Not published: only the timer reads it.
    var hoveredID: UUID?

    /// The timer each capture is waiting on. A new timer replaces the old
    /// one, and one that no longer matches does nothing when it fires.
    private var keepTimers: [UUID: UUID] = [:]

    /// After a change of delay, every waiting capture starts over with it.
    func restartKeepTimers() {
        for item in items where !item.falling && !item.away && isInInbox(item.id) { scheduleKeep(item.id) }
    }

    /// Moves a capture from ShotLine's folder once its time is up. While it
    /// is being held, dragged, edited or looked at, it waits a little longer.
    private func scheduleKeep(_ id: UUID, after delay: TimeInterval? = Line.keepDelay) {
        guard let delay else {
            keepTimers[id] = nil
            return
        }
        let timer = UUID()
        keepTimers[id] = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.keepTimers[id] == timer, !self.held.contains(id), self.isInInbox(id),
                  let item = self.items.first(where: { $0.id == id && !$0.falling }) else { return }
            if self.isBusy(item) {
                self.scheduleKeep(id, after: 2)
            } else {
                self.keep(id, quietly: true)
            }
        }
    }

    private func isBusy(_ item: Pegged) -> Bool {
        draggingID == item.id || pressedID == item.id || hoveredID == item.id
            || GrabView.isDragging || GrabView.isShowingMenu
            || Markup.shared.isEditing(item.url) || Trim.shared.isEditing(item.url)
            || QuickLook.shared.isVisible
    }

    /// Photos opened in another app, like Preview. Moving the file would pull
    /// it out from under the editor and the edit could not be saved, so these
    /// stay until the checkmark or the menu moves them. Markup and trimming
    /// say when they are done, so those photos come back instead.
    private var held: Set<UUID> = []

    /// Files ShotLine has just moved to the screenshots folder.
    private var justKept: Set<String> = []

    /// Every file hung since launch, by its identity on disk rather than its
    /// path. A photo dragged to the Desktop, or renamed there, is the same
    /// file under a new name, and a watcher would otherwise hang it again.
    private var hungFiles: Set<String> = []

    private func wasHung(_ url: URL) -> Bool {
        fileID(url).map(hungFiles.contains) ?? false
    }

    /// The volume and inode: kept by a move or a rename, new for a copy.
    private func fileID(_ url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Click: open the photo in the system Markup editor. Markup does not
    /// edit video, so a recording opens in the trimming editor instead.
    /// Its timer stops, and once the editor is up the photo leaves the line
    /// for it (`takeAway`); Done or Escape hangs it again with the full time
    /// ahead of it.
    func markup(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id && !$0.falling && !$0.away }) else { return }
        let item = items[i]
        if item.isRecording {
            Trim.shared.edit(item.url, size: item.thumb.size)
        } else {
            // Markup edits one file at a time.
            if Markup.shared.isOpen {
                NSSound.beep()
                return
            }
            guard Markup.shared.edit(item.url) else {
                // Opened in Preview instead, which never says when it is done.
                held.insert(id)
                return
            }
        }
        keepTimers[id] = nil
    }

    /// The editor is up: the photo leaves the line to fly into it.
    func takeAway(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        if hoveredID == id { hoveredID = nil }
        hitRects[id] = nil
        items[i].away = true
    }

    /// The editor is closing: the photo flies back from where it showed it.
    func editClosing(_ url: URL, from area: CGRect) {
        rehang(url, from: area)
    }

    /// The editor has closed and any edit is saved. A photo still away, from
    /// an editor that closed without warning, hangs again now.
    func editEnded(_ url: URL, from area: CGRect?) {
        if items.contains(where: { $0.url == url && $0.away && !$0.falling }) {
            rehang(url, from: area)
        } else {
            reloadThumbnail(for: url)
        }
    }

    /// The photo hangs again, showing any edit, flying back from the editor
    /// when it knows where that was.
    private func rehang(_ url: URL, from area: CGRect?) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }) else { return }
        if let thumb = makeThumbnail(url) {
            items[i].thumb = thumb
            items[i].modified = modificationDate(url)
        }
        let wasAway = items[i].away
        items[i].away = false
        if wasAway && area != nil { items[i].flying = true }
        let id = items[i].id
        if isInInbox(id) { scheduleKeep(id) }
        onRehung?(id, wasAway ? area : nil)
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
        items[i].modified = modificationDate(url)
    }

    /// Quick Look on this photo, with the rest of the line a key press away.
    func quickLook(_ id: UUID) {
        let live = items.filter { !$0.falling }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        QuickLook.shared.show(live.map(\.url), at: index)
    }

    /// After a change of size, every photo is redrawn sharp at the new one.
    func reloadThumbnails() {
        for i in items.indices where !items[i].falling {
            if let thumb = makeThumbnail(items[i].url) { items[i].thumb = thumb }
        }
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling }.map(\.url.path)
        UserDefaults.standard.set(paths, forKey: storeKey)
    }

    /// Everything comes back as it was. This runs before the line knows its
    /// screen, so the capacity is still the default one: hanging through
    /// `hang` would let photos fall off a wide screen's line at every launch.
    private func restore() {
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard !items.contains(where: { $0.url == url }), let thumb = makeThumbnail(url) else { continue }
            items.append(Pegged(url: url, thumb: thumb, modified: modificationDate(url)))
            if let file = fileID(url) { hungFiles.insert(file) }
        }
        // Captures left in ShotLine's folder at the last quit get their time too.
        for item in items where isInInbox(item.id) { scheduleKeep(item.id) }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func modificationDate(_ url: URL) -> Date? {
        // Not URL.resourceValues: those are cached, and the edit would go unseen.
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Screen recordings, as macOS saves them.
func isRecording(_ url: URL) -> Bool {
    ["mov", "mp4"].contains(url.pathExtension.lowercased())
}

/// The default size covers a card at twice its size in points, as on a
/// Retina screen, and no more: every photo on the line keeps one in memory.
func makeThumbnail(_ url: URL, maxPixels: Int = Int(320 * Layout.size.scale)) -> NSImage? {
    if isRecording(url) { return firstFrame(url, maxPixels: maxPixels) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A recording shows its first frame.
private func firstFrame(_ url: URL, maxPixels: Int) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
