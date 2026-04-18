import Foundation

enum StreamPlatform: String, CaseIterable, Identifiable, Codable {
    case twitch
    case youtube
    case tiktok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twitch: return "Twitch"
        case .youtube: return "YouTube"
        case .tiktok: return "TikTok"
        }
    }

    var rtmpIngestBaseURL: URL {
        switch self {
        case .twitch:
            return URL(string: "rtmp://live.twitch.tv/app")!
        case .youtube:
            return URL(string: "rtmp://a.rtmp.youtube.com/live2")!
        case .tiktok:
            return URL(string: "rtmp://push.tiktoklive.com/live")!
        }
    }
}
