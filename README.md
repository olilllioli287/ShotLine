<p align="center">
  <img src="docs/images/shotline-icon.png" width="128" height="128" alt="ShotLine 圖示：兩張截圖夾在曬衣繩上，右下角一個綠色勾勾">
</p>

<h1 align="center">ShotLine</h1>

<p align="center">
  截圖先掛在螢幕上方的曬衣繩上，過一會兒自動收進你的截圖檔案夾。
  <br>
  macOS 14 以上。改自 <a href="https://github.com/alejandrobujan/tendedero">Tendedero</a> 1.5.0，MIT 授權。
</p>

<br>

## 跟原版 Tendedero 不一樣的地方

- **自動收進截圖檔案夾**：截圖掛上曬衣繩後，過一段時間會自動搬到 macOS 原本存截圖的檔案夾（例如 `~/Desktop/螢幕擷圖`），然後離開曬衣繩。原版會一直留在 App 自己的檔案夾裡，繩子滿了就丟進垃圾桶。
- **右下角的勾勾**：滑鼠移到照片上，右下角會出現 ✓，按下去立刻搬走，不用等。右鍵選單也有「移到螢幕擷圖檔案夾」。
- **自動收回時間可調整**：選單列的「自動收回」可以選 15 秒、30 秒、3 分鐘或永不收回，預設 15 秒。截圖後曬衣繩會一直放下來，直到照片搬走才收起，這段時間勾勾都按得到。
- **編輯中的照片不會被搬走**：用「預覽」打開或用標示工具（Markup）編輯過的照片不會自動搬走，避免編到一半檔案不見、存不回去，編完按 ✓ 就好。滑鼠停在照片上、正在拖曳、右鍵選單開著、或「快速查看」開著時，計時也會等你。
- **拖進 App 後就收走**：照片拖進聊天視窗、終端機等 App 後，會離開曬衣繩並搬到截圖檔案夾。原版會一直掛著。
- **繩子滿了不會丟東西**：最舊的照片改成搬到截圖檔案夾，不再丟進垃圾桶。
- **繁體中文**：加上繁體中文（台灣用語）翻譯，選單裡多了「使用說明…」。
- **自己的名字和圖示**：依原作者的授權要求，改名為 ShotLine（bundle id `local.shotline.ShotLine`），換上藍綠色加綠勾勾的圖示，並拿掉指向 tendedero.app 的「檢查更新」。

<br>

## 操作方式

| 操作 | 效果 |
|:--|:--|
| 點一下 | 拷貝圖片 |
| 按住不放 | 用標示工具（Markup）編輯，錄影則是剪輯 |
| 雙擊 | 用「預覽」打開 |
| 用力按（觸控板） | 快速查看 |
| 拖到 App 裡 | 放一份拷貝進去，照片離開繩子、檔案搬到截圖檔案夾 |
| 拖到檔案夾 | 檔案搬過去，照片離開繩子 |
| 右下角 ✓ | 立刻搬到截圖檔案夾 |
| 左上角 ✕，或拖到垃圾桶 | 丟掉 |
| 滑鼠停在選單列 | 把曬衣繩放下來 |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>T</kbd> | 顯示或隱藏曬衣繩（可在選單列的「快速鍵」更改） |

<br>

## 怎麼運作

第一次開啟時打開「接管截圖」（選單列裡也能切換），ShotLine 會把 macOS 的截圖存放位置暫時改到自己的檔案夾 `~/Library/Application Support/ShotLine/Screenshots`，並關掉右下角的浮動縮圖，所以截圖一按下就會掛上繩子。原本的設定會先記下來，結束 ShotLine 或關掉這個選項時自動還原。照片要搬去的「截圖檔案夾」就是這個記下來的位置，沒有設定過的話是桌面。

不連網、沒有帳號、沒有分析，所有東西都留在你的 Mac 上。

<br>

## 從原始碼編譯

```sh
git clone https://github.com/olilllioli287/ShotLine.git
cd ShotLine
scripts/build-app.sh
cp -R build/ShotLine.app /Applications/
open /Applications/ShotLine.app
```

需要 Swift 工具鏈，Xcode 可有可無。本機編譯用的是臨時簽章（ad hoc），所以每次重新編譯後，macOS 可能會再問一次能不能存取桌面。

改了翻譯之後，執行 `swift scripts/check-strings.swift` 檢查有沒有缺漏。翻譯檔在 `Sources/ShotLine/Resources`，每個語言一個 `.lproj` 檔案夾。

<details>
<summary>程式檔案</summary>
<br>

| 檔案 | 負責 |
|:--|:--|
| `AppDelegate.swift` | 選單列、快速鍵、曬衣繩的放下與收起 |
| `Line.swift` | 繩上掛著什麼、可以對它們做什麼，以及自動收進截圖檔案夾的計時 |
| `PeggedView.swift` | 單張照片：玻璃框、夾子、✕ 和 ✓ |
| `GrabArea.swift` | 點擊、長按、拖放、角落按鈕 |
| `Inbox.swift` | 接管截圖設定並在結束時還原，記住原本的截圖檔案夾 |
| `Guide.swift` | 使用說明視窗 |
| `ScreenshotWatcher.swift` | 偵測新截圖 |
| `ClipboardWatcher.swift` | 偵測拷貝的圖片 |
| `Markup.swift` / `Trim.swift` | 編輯圖片、剪輯錄影並存回原檔 |
| `QuickLook.swift` | 快速查看 |
| `LinePanel.swift` / `LineView.swift` | 螢幕上方那條透明的長條和曬衣繩 |
| `FullScreen.swift` | 全螢幕 App 時自動隱藏 |

圖示由 `scripts/make-icon.swift` 用程式畫出來。

</details>

<br>

## 授權與致謝

ShotLine 改自 [Alejandro Buján](https://alejandrobujan.com) 的 [Tendedero](https://github.com/alejandrobujan/tendedero) 1.5.0。原始程式碼採 MIT 授權，原作者的版權聲明保留在 [LICENSE](LICENSE)。Tendedero 的名稱和圖示不在授權範圍內，所以這個改版用的是自己的名字和圖示。

`docs/` 裡的其他圖片和 `docs/i18n` 的多語說明是原版 Tendedero 的，保留下來供參考，內容描述的是原版。
