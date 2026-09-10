import Foundation
import Keystore_iOS
import KeyDerivation
import Individuality

enum ReferralLinkError: Error {
    case missingQueryItem(ReferralLink.QueryItem)
    case savingError(Error)
}

struct ReceivedReferral: Codable {
    let referralCode: Data
    let referrer: ProofOfInkPallet.PersonalId
}

final class ReferralLinkHandler {
    private let keystore: KeystoreProtocol
    private let jsonEncoder: JSONEncoder

    init(
        keystore: KeystoreProtocol = Keychain(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.keystore = keystore
        self.jsonEncoder = jsonEncoder
    }
}

extension ReferralLinkHandler: LinkHandler {
    func handle(_ url: URL) -> LinkHandlingOutcome {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .skipped
        }
        guard components.scheme == ReferralLink.scheme else {
            return .skipped
        }

        guard components.host == "\(ReferralLink.host)" else {
            return .skipped
        }

        guard let referralCodeString = components.queryItems?
            .first(where: { $0.name == ReferralLink.QueryItem.referralCode.rawValue })?.value,
            let referralCode = try? Data(hexString: referralCodeString) else {
            return .failed(ReferralLinkError.missingQueryItem(.referralCode))
        }

        guard let referrerString = components.queryItems?
            .first(where: { $0.name == ReferralLink.QueryItem.referrerId.rawValue })?.value,
            let referrer = UInt64(referrerString)
        else {
            return .failed(ReferralLinkError.missingQueryItem(.referrerId))
        }

        let resolvedData = ReceivedReferral(referralCode: referralCode, referrer: referrer)

        do {
            let jsonData = try jsonEncoder.encode(resolvedData)
            try keystore.saveKey(jsonData, with: KeystoreTag.receivedRefferalTag())
            return .handled
        } catch {
            return .failed(ReferralLinkError.savingError(error))
        }
    }
}
