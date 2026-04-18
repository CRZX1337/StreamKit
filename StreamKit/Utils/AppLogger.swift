import Foundation
import OSLog

enum AppLogger {
    static let subsystem = "com.example.StreamKit"
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let stream = Logger(subsystem: subsystem, category: "stream")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
