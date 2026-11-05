import AppKit

// HubLink：讓「Hub 集合面板」（~/claude-projects/hub）管這個 App。
// 正本在 ~/claude-projects/hub/HubLink/HubLink.swift，各 App 各放一份，改了要一起改。
//
// 面板 → App（DistributedNotificationCenter，object 一律是目標 App 的 bundle id）：
//   com.local.hub.statusItem  userInfo["visible"] = Bool   藏／顯示選單列圖示（App 自己記在 hub.statusItemHidden）
//   com.local.hub.open                                     叫出原本的選單或面板（圖示藏起來時彈在滑鼠旁邊）
//   com.local.hub.reload                                   面板改了這個 App 的設定，請重讀
//   com.local.hub.action（userInfo["action"]）            面板要這個 App 做一件事（App 自己定義有哪些）
// 在 Finder 再打開一次 App（reopen）也會叫出選單，圖示藏起來時還是找得到它。
// Info.plist 要加 <key>HubLink</key><integer>1</integer>，面板看到才會顯示這些開關。
//
// 對外的函式都可以從任何地方呼叫（各 App 的 AppDelegate 有的沒標 @MainActor），
// 但一定要在主執行緒上：AppKit 的 delegate 方法、選單動作、主佇列的通知都是。

enum HubLink {
    static let hiddenKey = "hub.statusItemHidden"

    @MainActor private static var item: () -> NSStatusItem? = { nil }
    @MainActor private static var canHide: () -> Bool = { true }
    @MainActor private static var openHandler: (() -> Void)?
    @MainActor private static var observers: [NSObjectProtocol] = []

    /// 建好 NSStatusItem 之後呼叫一次。
    /// - canHide：有些模式圖示本身就是主角（例如桌寵的選單列模式），這時不准藏
    /// - open：叫出主畫面的做法；不給就彈出 statusItem.menu
    /// - reload：面板改了設定後要做的事
    /// - action：面板送來的指令（例如 Toolbox 的 "gameMode.toggle"）；不給就不接
    static func install(statusItem: @escaping () -> NSStatusItem?,
                        canHide: @escaping () -> Bool = { true },
                        open: (() -> Void)? = nil,
                        reload: (() -> Void)? = nil,
                        action: ((String) -> Void)? = nil) {
        MainActor.assumeIsolated {
            item = statusItem
            self.canHide = canHide
            openHandler = open
            refreshNow()

            let id = Bundle.main.bundleIdentifier ?? ""
            let center = DistributedNotificationCenter.default()
            observers.append(center.addObserver(forName: Notification.Name("com.local.hub.statusItem"), object: id, queue: .main) { note in
                let visible = (note.userInfo?["visible"] as? Bool) ?? true
                UserDefaults.standard.set(!visible, forKey: hiddenKey)
                HubLink.refresh()
            })
            observers.append(center.addObserver(forName: Notification.Name("com.local.hub.open"), object: id, queue: .main) { _ in
                HubLink.open()
            })
            if let reload {
                observers.append(center.addObserver(forName: Notification.Name("com.local.hub.reload"), object: id, queue: .main) { _ in
                    reload()
                })
            }
            if let action {
                observers.append(center.addObserver(forName: Notification.Name("com.local.hub.action"), object: id, queue: .main) { note in
                    if let name = note.userInfo?["action"] as? String { action(name) }
                })
            }
        }
    }

    /// 使用者要藏圖示（不管目前模式准不准藏）
    static var wantsHidden: Bool { UserDefaults.standard.bool(forKey: hiddenKey) }

    /// 依設定與模式套用圖示顯示；模式改變時（例如桌寵切到選單列模式）也要呼叫
    static func refresh() {
        MainActor.assumeIsolated { refreshNow() }
    }

    @MainActor private static func refreshNow() {
        guard let statusItem = item() else { return }
        let visible = !(wantsHidden && canHide())
        if statusItem.isVisible != visible { statusItem.isVisible = visible }
    }

    /// 圖示現在看得到嗎（藏起來時面板要彈在滑鼠旁邊、不能對齊圖示）
    static var statusItemShown: Bool {
        MainActor.assumeIsolated {
            guard let statusItem = item() else { return false }
            return statusItem.isVisible && statusItem.button?.window != nil
        }
    }

    /// 叫出主畫面：有自訂做法就用，沒有就彈出選單
    static func open() {
        MainActor.assumeIsolated {
            if let openHandler { openHandler() } else { popUpMenu() }
        }
    }

    /// 在 Finder 再打開一次 App 時呼叫（applicationShouldHandleReopen）。
    /// 圖示看得到時使用者可以直接點，就不多事；藏起來時才叫出來
    static func reopen() {
        // 等「重新開啟」這個 Apple Event 處理完再彈選單，不要在事件處理途中跑選單的事件迴圈
        DispatchQueue.main.async {
            if !statusItemShown { open() }
        }
    }

    /// 彈出選單列圖示的選單：圖示看得到就從圖示往下彈，藏起來就彈在滑鼠位置
    static func popUpMenu() {
        MainActor.assumeIsolated {
            guard let statusItem = item(), let menu = statusItem.menu else { return }
            NSApp.activate()
            if statusItem.isVisible, statusItem.button?.window != nil, let button = statusItem.button {
                button.performClick(nil)
            } else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }
}
