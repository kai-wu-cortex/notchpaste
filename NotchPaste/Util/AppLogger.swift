import os

/// 项目统一日志入口，subsystem = com.notchpaste.app。
enum AppLogger {
    static let app = Logger(subsystem: "com.notchpaste.app", category: "app")
    static let clipboard = Logger(subsystem: "com.notchpaste.app", category: "clipboard")
    static let store = Logger(subsystem: "com.notchpaste.app", category: "store")
    static let paste = Logger(subsystem: "com.notchpaste.app", category: "paste")
    static let hotkey = Logger(subsystem: "com.notchpaste.app", category: "hotkey")
    static let ui = Logger(subsystem: "com.notchpaste.app", category: "ui")
}
