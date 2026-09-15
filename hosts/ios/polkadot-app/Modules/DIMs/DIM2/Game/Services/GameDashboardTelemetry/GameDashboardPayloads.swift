import Foundation

enum GameDashboardPayloads {
    struct Registration: Encodable {
        let who: String
        let usernameAccountId: String?
        let username: String?
        let timestamp: Int64
    }

    struct Reporting: Encodable {
        let who: String
        let peers: [[Peer]]
        let timestamp: Int64

        struct Peer: Encodable {
            let id: String
            let state: String
        }
    }

    struct End: Encodable {
        let who: String
        let reports: [[Report]]
        let timestamp: Int64

        struct Report: Encodable {
            let id: String
            let verdict: String
        }
    }
}

enum GameDashboardVerdict: String {
    case person
    case notperson
}
