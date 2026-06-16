# NotchPaste — 设计文档

**日期**：2026-06-16
**作者**：Kyle（与 Claude 协同 brainstorm）
**状态**：待批准

---

## 1. 概述

**NotchPaste** 是一款 macOS 剪贴板历史管理应用。它常驻 MacBook 刘海区域，以 Dynamic Island 风格的 pill 形态展示状态；点击或快捷键展开后呈现侧栏 + 列表布局的剪贴板历史面板。

核心差异点：**自动避让其他刘海类应用**（NotchNook、Boring.notch、AlcoveX 等）。当检测到这些应用启动并占用刘海周围空间时，NotchPaste 会沿菜单栏滑动迁移到空闲一侧；左右皆被占用时，缩进菜单栏继续工作。

支持 macOS 14 Sonoma+，开源（MIT），通过 GitHub Release 分发 `.dmg`/`.zip`。

---

## 2. 目标与非目标

### 目标

- 在刘海区提供低打扰、高可访问的剪贴板历史入口
- 支持 **文本、图片、文件** 三种类型的剪贴板内容
- 与同类刘海应用和平共处，自动让位
- 尊重用户隐私：识别 `org.nspasteboard.ConcealedType` 并跳过敏感内容
- 提供 **搜索、类型过滤、收藏置顶** 三大组织能力
- 默认提供"自动 ⌘V 注入"的流畅粘贴体验，可降级为复制后手动粘贴

### 非目标（v1 不做）

- 富文本（HTML/RTF）的样式保留 —— 仅记录纯文本回退
- 跨设备同步（iCloud / 自建后端）
- OCR / 图片文字识别
- 来源应用过滤（按"从哪个 app 复制"分组）
- 剪贴板内容的二次编辑器
- Mac App Store 上架（沙盒限制阻碍核心功能）
- 跨 Linux / Windows 平台
- 多窗口 / 多 Space 独立实例（一个全局实例，跨 Space 共享）

---

## 3. 用户体验

### 3.1 常驻形态（pill）

平时屏幕顶部、刘海右侧延伸出一个 **Dynamic Island 风格 pill**：

- 黑色圆角条，与刘海融合
- 显示一个状态点 + 当前历史条数（如"42"）
- **复制事件触发时**：pill 短暂膨胀（~600ms）显示新内容预览（前 30 字符或缩略图），随后收回
- **位置形态**：pill 形状左右对称 —— 在右侧时左缘贴刘海、右缘圆角；在左侧时右缘贴刘海、左缘圆角；视觉始终像"从刘海里长出来"
- **避让触发时**：pill 沿菜单栏滑动 300ms 迁移到另一侧；左右都被占用时，缩小淡出 → 菜单栏图标淡入

### 3.2 展开面板

**触发方式**：
1. 鼠标点击 pill
2. 全局快捷键（默认 ⇧⌘V，可在偏好设置中重绑）

**布局**（侧栏 + 列表）：
- 总宽 480pt，高度根据列表项数量在 320–560pt 之间自适应（约 8–14 项可见，超出滚动）。从刘海正下方滑出（spring 动画 ~250ms）
- 面板水平居中对齐刘海中线，与当前 pill 位置无关 —— 即使 pill 在左侧或缩进菜单栏，展开后仍出现在刘海下方
- **左侧栏**（100pt 宽）：分类导航
  - All · {总数}
  - 📌 Pinned · {数}
  - 📝 Text · {数}
  - 🖼 Image · {数}
  - 📄 File · {数}
- **右侧主区**：
  - 顶部搜索框（模糊匹配文本预览、文件名）
  - 下方剪贴板项列表，每项一行：图标/缩略图 + 预览文本 + 时间戳

**键盘交互**：
- ↑↓ 选择项
- Enter / ⌘1..⌘9 粘贴并关闭面板
- ⌘F 聚焦搜索
- ⌘P 切换置顶
- ⌘Delete 删除项
- Esc 关闭面板

### 3.3 粘贴流程

1. 用户在面板中选中一项 → Enter
2. 面板关闭、内容写入系统剪贴板
3. **如果"辅助功能"权限已授予**：模拟 ⌘V 按键注入到当前焦点应用
4. **未授权**：仅写入剪贴板，用户手动 ⌘V

首次启动时引导用户授予"辅助功能"权限；可在偏好设置中关闭自动粘贴回退到手动模式。

### 3.4 偏好设置

通过菜单栏图标右键或面板齿轮菜单进入：

- **历史**：最大条数（10–10000，默认 200）、过期天数（1–365，默认 7）
- **快捷键**：展开面板的全局快捷键
- **粘贴行为**：自动 ⌘V 注入开关
- **避让**：白名单 app 列表（默认包含已知刘海 app，可手动增删）
- **启动**：登录时启动开关
- **清除**：一键清空所有历史
- **关于**：版本号、GitHub 链接、检查更新

---

## 4. 系统架构

### 4.1 架构总览

NotchPaste 是一个 LSUIElement = true 的 macOS 应用（无 Dock 图标），由以下模块组成：

```
NotchPaste.app
├── App (SwiftUI App + AppDelegate)
├── Pill Window (NSPanel + SwiftUI 内容)
├── Expanded Panel Window (NSPanel + SwiftUI 内容)
├── Menu Bar Item (NSStatusItem)
├── Settings Window (SwiftUI Window)
└── Core Services
    ├── ClipboardMonitor      — 轮询 NSPasteboard
    ├── ClipboardStore        — 持久化历史
    ├── NotchAppDetector      — 监听其他刘海 app
    ├── PositionManager       — 决定 pill 位置 + 调度动画
    ├── PasteService          — 自动粘贴注入
    ├── HotkeyService         — 全局快捷键
    └── PreferencesStore      — UserDefaults 包装
```

### 4.2 核心模块职责

#### ClipboardMonitor
- 通过 `Timer` 每 0.5s 检查 `NSPasteboard.general.changeCount`
- 变化时读取 `NSPasteboard.types`，按优先级提取：
  1. 检测 `org.nspasteboard.ConcealedType` → 跳过整条
  2. `public.file-url` → 文件类型
  3. `public.image` → 图片类型
  4. `public.utf8-plain-text` → 文本类型
- 提取到的项 → `ClipboardStore.add(item)`
- **接口**：`AsyncStream<ClipboardItem>` 给监听者；不直接调 UI 层

#### ClipboardStore
- 持久化抽象，支持类型为 `ClipboardItem`：
  ```swift
  struct ClipboardItem {
    let id: UUID
    let type: ItemType  // .text(String), .image(Data), .file([URL])
    let createdAt: Date
    var pinned: Bool
    var sourceAppBundleID: String?
  }
  ```
- 实现：SQLite（GRDB.swift）+ 大图片/文件落盘到 Application Support
- 容量与过期：后台任务每 5 分钟清理超出 `maxItems` 或 `expireDays` 的非置顶项
- **接口**：
  - `add(_ item: ClipboardItem)`
  - `delete(id: UUID)`
  - `togglePin(id: UUID)`
  - `query(filter: Filter, search: String?) -> [ClipboardItem]`
  - `count(by: ItemType?) -> Int`
- 不知道 UI 存在；通过 `Combine.Publisher<[ClipboardItem]>` 通知变化

#### NotchAppDetector
- 监听 `NSWorkspace.shared.notificationCenter`：
  - `didLaunchApplicationNotification`
  - `didTerminateApplicationNotification`
  - `didActivateApplicationNotification`
- 维护已知刘海 app bundle ID 白名单（用户可扩展）：
  ```
  com.lo.cas.dynamic-notch       (NotchNook)
  com.thealexandev.boringnotch   (Boring.notch)
  com.alvarofierro.alcove        (AlcoveX)
  ...
  ```
- **接口**：`@Published var occupiedSides: Set<NotchSide>`（`.left`、`.right`）
  - 一个白名单 app 在前台/运行 → 视为占据其对应"偏好侧"（默认右侧；用户可在偏好设置中调整每个 app 的占位偏好）

#### PositionManager
- 订阅 `NotchAppDetector.occupiedSides` 和当前屏幕分辨率
- 计算目标位置：
  ```
  if occupied is empty               → pillRight (默认)
  elif occupied == [.right]          → pillLeft
  elif occupied == [.left]           → pillRight
  else (both occupied)               → menubarOnly
  ```
- 调用 PillWindow 执行动画（300ms spring，水平滑动；缩到菜单栏时 200ms 淡出 + 200ms 菜单栏图标淡入）
- 监听 `NSScreen` 变化（外接显示器、分辨率变化）触发重新定位
- **接口**：`@Published var currentPosition: PillPosition`

#### PasteService
- 检查 `AXIsProcessTrustedWithOptions(...)`
- 已授权且偏好开启 → 使用 `CGEvent` 模拟 ⌘V：
  ```
  let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
  down?.flags = .maskCommand
  // ... post to .cghidEventTap
  ```
- 未授权 → 仅写剪贴板；首次失败弹一次性引导
- **接口**：`paste(_ item: ClipboardItem)`

#### HotkeyService
- 使用 [HotKey](https://github.com/soffes/HotKey) Swift package（或 Carbon `RegisterEventHotKey` 直接封装）
- 注册全局快捷键 → 触发 `togglePanel()` 通知

### 4.3 窗口实现

#### Pill Window
- `NSPanel` 子类
- `styleMask = [.borderless, .nonactivatingPanel]`
- `level = .statusBar + 1`（在菜单栏之上，低于全屏 alert）
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- `isMovable = false`
- `backgroundColor = .clear`
- 内容是 SwiftUI 视图：自定义形状（左侧/右侧贴边的圆角矩形），使用 `Path` 绘制

#### Expanded Panel Window
- `NSPanel` 子类（同样的 mask/level/collectionBehavior）
- 出现时：从 pill 当前 frame 向下"展开"，用 `NSAnimationContext` + 内部 SwiftUI 的 `.matchedGeometryEffect`/`.transition` 实现入场
- 失焦自动收起（`windowDidResignKey` → `close()`）

#### Menu Bar Item
- `NSStatusBar.system.statusItem(withLength:)`
- 默认隐藏；当 `PositionManager.currentPosition == .menubarOnly` 时显示
- 点击 → 弹出和 Expanded Panel 相同内容的 popover（位置改为图标下方）

### 4.4 数据流

```
[用户 ⌘C] → NSPasteboard
              ↓ (changeCount 改变)
       ClipboardMonitor → ClipboardItem
              ↓
       ClipboardStore (SQLite + Files)
              ↓ (Publisher 推送)
       UI 视图（pill 预览膨胀；面板列表刷新）

[用户启动 NotchNook] → NSWorkspace.didLaunch
                       ↓
                  NotchAppDetector
                       ↓ (occupiedSides 改变)
                  PositionManager
                       ↓ (currentPosition 改变)
              Pill Window 动画 + Menu Bar Item 切换
```

---

## 5. 错误处理

### 关键失败模式

| 失败 | 检测 | 行为 |
|---|---|---|
| 辅助功能权限被撤销 | `AXIsProcessTrusted()` 返回 false | Toast 提示用户 → 退化为复制后手动 ⌘V |
| 数据库损坏 | GRDB 抛出 SQLite 错误 | 备份当前 DB 到 `~/Library/Application Support/NotchPaste/db.broken-{date}.sqlite` → 重建空 DB → 通知用户 |
| 历史磁盘空间满 | 写入失败 | 暂停写入，触发清理；清理后仍失败 → 切换为内存模式 + 警告 |
| 快捷键被其他 app 抢占 | `HotKey` 注册失败 | 偏好设置标红当前快捷键，提示用户重绑 |
| 屏幕配置无刘海（外接显示器） | 检测主屏幕安全区域 inset | 退化为菜单栏图标 + 快捷键模式（隐藏 pill） |
| 自动粘贴注入失败 | `CGEvent.post` 异常 / 焦点 app 不响应 | 仅保证已写入剪贴板；不重试，不打扰 |
| 系统剪贴板含有 ConcealedType | `NSPasteboard.types.contains("org.nspasteboard.ConcealedType")` | 跳过整条记录，不入库，不预览 |

### 日志

- 使用 `os.Logger`，subsystem = `com.notchpaste.app`
- 默认级别 INFO；偏好设置中可开启 DEBUG（写到 `~/Library/Logs/NotchPaste/`）

---

## 6. 测试策略

### 单元测试（Swift Testing）

- `ClipboardStore`：增删改查、容量裁剪、过期清理、置顶排序
- `NotchAppDetector`：模拟 NSWorkspace 通知 → 验证 `occupiedSides` 状态机
- `PositionManager`：给定 `occupiedSides` 输入 → 验证目标位置正确
- `ClipboardMonitor` 类型识别：构造各种 `NSPasteboardItem` → 验证类型分类、ConcealedType 跳过

### 集成测试

- 启动 app → 复制内容 → 验证 pill 预览膨胀 + 历史项落库
- 模拟 NotchNook 启动 → 验证 pill 滑动到左侧
- 模拟左右都被占 → 验证菜单栏图标出现、pill 隐藏

### 手动验证清单

- [ ] M1 / M2 / M3 / M4 各档 MacBook 刘海尺寸适配（运行时计算屏幕安全区域）
- [ ] 双显示器（主屏带刘海、副屏不带）切换
- [ ] 全屏应用 / Mission Control / Stage Manager 共存
- [ ] 暗色 / 亮色模式
- [ ] macOS 14, 15, 16 各一台测试

---

## 7. 安全与隐私

- **数据本地化**：剪贴板历史仅保存在 `~/Library/Application Support/NotchPaste/`，不上传任何服务器
- **敏感跳过**：识别 `org.nspasteboard.ConcealedType`（[nspasteboard.org 标准](https://nspasteboard.org)），1Password、Bitwarden 等密码管理器主动设置此标记
- **权限最小化**：
  - 辅助功能（自动粘贴）：可选，用户可拒绝
  - 自动启动：可选，用户可关闭
  - 不请求文件全盘访问、麦克风、摄像头、位置
- **加密**：v1 不加密本地数据库（剪贴板历史本身就是用户在屏幕上看过的内容）；v2 可选 FileVault 之外的应用层加密

---

## 8. 项目结构

```
NotchPaste/
├── NotchPaste.xcodeproj
├── NotchPaste/
│   ├── App/
│   │   ├── NotchPasteApp.swift       — @main + AppDelegate
│   │   └── Assets.xcassets
│   ├── Core/
│   │   ├── ClipboardMonitor.swift
│   │   ├── ClipboardStore.swift
│   │   ├── ClipboardItem.swift
│   │   ├── NotchAppDetector.swift
│   │   ├── PositionManager.swift
│   │   ├── PasteService.swift
│   │   ├── HotkeyService.swift
│   │   └── PreferencesStore.swift
│   ├── UI/
│   │   ├── Pill/
│   │   │   ├── PillWindow.swift
│   │   │   └── PillView.swift
│   │   ├── Panel/
│   │   │   ├── PanelWindow.swift
│   │   │   ├── PanelView.swift
│   │   │   ├── SidebarView.swift
│   │   │   ├── ItemListView.swift
│   │   │   └── ItemRowView.swift
│   │   ├── MenuBar/
│   │   │   └── MenuBarController.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   └── Util/
│       ├── ScreenGeometry.swift      — 计算刘海周围安全区
│       └── Logger.swift
├── NotchPasteTests/
├── Packages.swift                    — SPM deps: GRDB.swift, HotKey
├── README.md
├── LICENSE                           — MIT
└── .github/
    └── workflows/
        └── release.yml               — 构建 + 公证 + 发布 dmg
```

---

## 9. 发布流程

- **构建**：Xcode → Archive → Developer ID 签名
- **公证**：`xcrun notarytool submit ... --wait` 后 `stapler staple`
- **打包**：使用 [create-dmg](https://github.com/sindresorhus/create-dmg) 生成 .dmg
- **GitHub Release**：上传 .dmg + 校验和（SHA-256）
- **CI**：推 tag `v*.*.*` 时自动跑 `.github/workflows/release.yml`
- **更新通知**：使用 [Sparkle](https://sparkle-project.org)（v2 加入；v1 用 GitHub Release 即可）
- **文档**：README 中的截图、GIF（避让动画）、安装说明、权限说明

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| Apple 改动菜单栏/刘海布局 API | 高 | 把屏幕几何计算集中到 `ScreenGeometry.swift`；OS 升级后只改这一个文件 |
| 其他刘海 app 的 bundle ID 我们不知道 | 中 | 偏好设置中允许用户手动添加 bundle ID；提供"启动 app 探测器"工具 |
| 自动粘贴在某些 app（如 VS Code 终端）失败 | 中 | 检测前台 bundle ID，列入"已知不兼容列表" → 自动退化为手动 ⌘V |
| 大图片/大文件导致 SQLite 膨胀 | 中 | 大于 1MB 的内容走文件系统，DB 只存路径引用 |
| 公证失败导致用户被 Gatekeeper 拦截 | 中 | README 加"右键打开"教程；公证失败时阻塞 release |
| 用户没有 Developer ID | 低（开发者本人问题） | 文档中说明：v1 暂不签名；用户首次启动右键打开。后续买证书后再切换 |

---

## 11. 里程碑

**v0.1（MVP）**
- 文本剪贴板捕获 + 持久化
- pill 显示在右侧（不避让）
- 展开面板（仅文本列表 + 搜索）
- 全局快捷键 + 自动粘贴

**v0.2（核心功能完整）**
- 图片、文件类型支持
- 类型过滤、收藏置顶
- 偏好设置面板
- ConcealedType 处理

**v0.3（避让能力）**
- NotchAppDetector + PositionManager
- 滑动动画
- 菜单栏图标 fallback

**v1.0（首次公开发布）**
- 公证签名
- README + 演示 GIF
- GitHub Release CI
- 至少 3 台不同 macOS 版本测试通过

---

## 12. 开放问题（非阻塞）

- 是否需要"快速复制"模式：连按 ⇧⌘V 直接粘贴上一项（暂不做，听用户反馈再决定）
- 是否支持文本片段模板（含变量替换）—— v2 候选
- iCloud 同步 —— v2+ 候选，需评估隐私边界

---

**文档结束。** 等待用户审核。
