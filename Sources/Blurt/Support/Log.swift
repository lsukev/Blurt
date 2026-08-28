import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.lsukev.blurt", category: "audio")
    static let speech = Logger(subsystem: "com.lsukev.blurt", category: "speech")
    static let hotkey = Logger(subsystem: "com.lsukev.blurt", category: "hotkey")
    static let inject = Logger(subsystem: "com.lsukev.blurt", category: "inject")
    static let app = Logger(subsystem: "com.lsukev.blurt", category: "app")
}
