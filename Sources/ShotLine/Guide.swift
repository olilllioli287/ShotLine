import AppKit
import SwiftUI

/// The user guide, opened from the menu bar. Written in Traditional Chinese:
/// this build of ShotLine is for one person.
@MainActor
final class Guide: NSObject, NSWindowDelegate {
    static let shared = Guide()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L("User Guide")
            window.contentView = NSHostingView(rootView: GuideView())
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
    }
}

private struct GuideView: View {
    private let sections: [(String, [String])] = [
        ("ShotLine 是什麼", [
            "截圖後，照片會先掛在螢幕上方的曬衣繩上，讓你拷貝、拖曳或編輯。",
            "掛上 15 秒後，照片會自動搬到「螢幕擷圖」檔案夾（桌面上那個），然後離開曬衣繩，曬衣繩也跟著收起來。",
            "等多久可以在選單列的「自動收回」改：15 秒、30 秒、3 分鐘或永不收回。永不收回時，照片會一直掛著，等你按 ✓ 或用快速鍵收起。",
            "滑鼠停在照片上、正在拖曳、右鍵選單打開、或「快速查看」開著時，會等你用完再搬。",
        ]),
        ("照片上的按鈕", [
            "右下角 ✓：立刻搬到「螢幕擷圖」，不用等 15 秒。",
            "左上角 ✕：丟到垃圾桶（不保留）。要救回來可以去垃圾桶找。",
            "兩個按鈕都要滑鼠移到照片上才會出現。",
        ]),
        ("對照片的操作", [
            "點一下：照片往下飛到螢幕中間放大，打開標示工具（Markup）畫線、加字。按「完成」存回原檔，按 Esc 不存；兩種都會讓照片縮小飛回繩上。錄影則是剪輯。",
            "按住不放：拷貝圖片，可以直接貼到聊天或文件裡。",
            "雙擊：取下照片，跟左上角 ✕ 一樣。",
            "用力按（觸控板）：快速查看，左右鍵看其他照片。",
            "拖到 App 裡（例如聊天視窗、終端機）：放一份拷貝進去，照片隨即離開繩子，檔案搬到「螢幕擷圖」。",
            "拖到檔案夾或桌面：檔案搬過去，照片離開繩子。",
            "拖到垃圾桶：刪除。",
            "右鍵：上面這些功能的選單，另外有「打開」（用「預覽」）、「移到螢幕擷圖檔案夾」和「取下左側／右側全部」。",
        ]),
        ("編輯中的照片", [
            "用標示工具編輯時，照片會先從繩上取下，自動收回的倒數也停住。按「完成」或 Esc 後照片掛回繩上，倒數從頭重新算。",
            "用「預覽」打開的照片不會自動搬走，避免編到一半檔案不見、存不回去。編輯完按右下角 ✓ 搬到「螢幕擷圖」。",
            "曬衣繩滿了的時候，最舊的照片會自動搬到「螢幕擷圖」，不會被丟掉。",
        ]),
        ("選單列的選項", [
            "顯示／隱藏曬衣繩：也可以用快速鍵 Control-Option-T。",
            "全部取下：繩上的照片全部丟到垃圾桶。",
            "接管截圖：打勾時截圖先掛到繩上。取消打勾就恢復成直接存到「螢幕擷圖」，不經過繩子。",
            "掛上拷貝的圖片：拷貝的圖片也掛上繩。",
            "放下曬衣繩：設定什麼時候自動把繩子放下來。",
            "同時監看檔案夾：其他檔案夾有新圖片時也掛上繩。",
            "自動收回：照片多久後自動搬走、曬衣繩多久後收起。",
            "繩上保留／大小：繩上最多幾張、照片大小。",
            "打開截圖檔案夾：打開 ShotLine 暫放截圖的地方。",
        ]),
        ("關掉或移除", [
            "選單列的「結束 ShotLine」會把截圖存放位置還原成「螢幕擷圖」，之後截圖就照 macOS 原本的方式存。",
            "原始碼在 ~/claude-projects/ShotLine，App 在「應用程式」檔案夾。",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections, id: \.0) { title, lines in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        ForEach(lines, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(line).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
