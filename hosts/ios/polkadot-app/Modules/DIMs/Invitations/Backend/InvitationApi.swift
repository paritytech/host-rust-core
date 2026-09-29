import Foundation
import Operation_iOS
import SubstrateSdk

enum InvitationApi {
    static let chainId = AppConfig.Chains.usernameChain

    case game(account: AccountAddress)
    case proofOfInk(account: AccountAddress)
}

extension InvitationApi: URLConvertible {
    var url: URL {
        var components = URLComponents(string: urlString)
        components?.queryItems = queryItems
        guard let url = components?.url(relativeTo: AppConfig.Backend.baseUrl) else {
            assertionFailure()
            return AppConfig.Backend.baseUrl
        }
        return url
    }

    var httpMethod: String {
        switch self {
        case .game,
             .proofOfInk:
            HttpMethod.post.rawValue
        }
    }

    private var urlString: String {
        switch self {
        case .game,
             .proofOfInk:
            "api/v1/invitation-ticket/claim"
        }
    }

    private var queryItems: [URLQueryItem]? {
        nil
    }

    var params: Encodable? {
        switch self {
        case let .game(account):
            [
                "who": account,
                "dim": "Game"
            ]
        case let .proofOfInk(account):
            [
                "who": account,
                "dim": "ProofOfInk"
            ]
        }
    }
}
