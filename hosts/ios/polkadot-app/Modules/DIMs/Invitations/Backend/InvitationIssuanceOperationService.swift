import Foundation
import KeyDerivation
import Operation_iOS
import ChainRegistry

protocol InvitationIssuanceServicing {
    func issueInvitation(type: Invitation.InvitationType) async throws -> IssueInvitationResponse
}

final class InvitationIssuanceService: InvitationIssuanceServicing {
    enum IssuanceError: Error {
        case failedToFetchCandidateAddress
    }

    private let chain: ChainModel
    private let candidate: WalletManaging
    private let tokenProvider: JWTTokenProviding
    private let session: URLSession

    init(
        chain: ChainModel,
        candidate: WalletManaging,
        tokenProvider: JWTTokenProviding,
        session: URLSession = .shared
    ) {
        self.chain = chain
        self.candidate = candidate
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func issueInvitation(type: Invitation.InvitationType) async throws -> IssueInvitationResponse {
        guard let candidateAddress = try? candidate.fetchAccount(for: chain).toAddress() else {
            throw IssuanceError.failedToFetchCandidateAddress
        }

        let endpoint: InvitationApi =
            switch type {
            case .game:
                .game(account: candidateAddress)
            case .tattoo:
                .proofOfInk(account: candidateAddress)
            }

        return try await tokenProvider.withAuthorizedToken { [session] token in
            var request = URLRequest(url: endpoint.url)
            request.httpMethod = endpoint.httpMethod
            request.setValue(
                HttpContentType.json.rawValue,
                forHTTPHeaderField: HttpHeaderKey.contentType.rawValue
            )

            let modifier = BearerTokenRequestModifier(token: token)
            try modifier.visit(request: &request)

            if let bodyParams = endpoint.params {
                request.httpBody = try JSONEncoder().encode(bodyParams)
            }

            let (data, urlResponse) = try await session.data(for: request)

            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw NetworkBaseError.unexpectedResponseObject
            }

            guard let statusCode = BackendStatusCode(rawValue: httpResponse.statusCode) else {
                throw NetworkResponseError.unexpectedStatusCode
            }

            guard statusCode.isOk else {
                let details = String(data: data, encoding: .utf8)
                throw BackendApiError(statusCode: statusCode, details: details)
            }

            return try JSONDecoder().decode(IssueInvitationResponse.self, from: data)
        }
    }
}
