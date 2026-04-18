import Foundation

struct StreamDestination: Identifiable, Hashable, Codable {
    let id: UUID
    let platform: StreamPlatform
    var streamKey: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        platform: StreamPlatform,
        streamKey: String = "",
        isEnabled: Bool = false
    ) {
        self.id = id
        self.platform = platform
        self.streamKey = streamKey
        self.isEnabled = isEnabled
    }
}
