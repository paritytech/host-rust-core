import Foundation

struct TattooMetadata: Codable, Equatable {
    struct Info: Codable, Equatable {
        let name: String
        let description: String?
        let mime: String
        let size: String?
        let media: String
    }

    let version: Int
    let metadata: Info
}
