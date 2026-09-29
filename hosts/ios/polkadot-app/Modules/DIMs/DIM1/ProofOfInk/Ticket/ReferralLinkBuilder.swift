import Foundation
import Individuality

enum ReferralLink {
    enum QueryItem: String, CustomStringConvertible {
        case referralCode
        case referrerId

        var description: String { rawValue }
    }

    static var host: String { "referral" }
    static var scheme: String { AppConfig.DeepLink.scheme }
}

protocol ReferralLinkBuilderProtocol {
    func buildReferralLink(
        ticket: ReferralTicketKey,
        personalId: PeoplePallet.PersonalId
    ) -> URL?
}

final class ReferralLinkBuilder: ReferralLinkBuilderProtocol {
    func buildReferralLink(
        ticket: ReferralTicketKey,
        personalId: PeoplePallet.PersonalId
    ) -> URL? {
        let referralCode = ticket.seed.toHex()
        var components = URLComponents()
        components.scheme = ReferralLink.scheme
        components.host = ReferralLink.host
        components.queryItems = [
            URLQueryItem(name: ReferralLink.QueryItem.referralCode.rawValue, value: referralCode),
            URLQueryItem(name: ReferralLink.QueryItem.referrerId.rawValue, value: String(personalId))
        ]
        return components.url
    }
}
