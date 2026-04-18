import Foundation
import CoreGraphics

struct StreamingConfig {
    var videoBitrate: Int = 2_500_000
    var audioBitrate: Int = 128_000
    var frameRate: Int = 30
    var keyFrameInterval: Int = 2
    var sampleRate: Double = 44_100
    var resolution: CGSize = CGSize(width: 1280, height: 720)

    static let `default` = StreamingConfig()
}
