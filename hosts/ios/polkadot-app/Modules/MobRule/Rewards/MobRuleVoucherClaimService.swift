import Foundation
import Individuality
import KeyDerivation
import ChainRegistry

protocol MobRuleVoucherClaimServicing {}

final class MobRuleVoucherClaimService {
    private let chain: ChainModel
    private let selectedWallet: WalletManaging
    private let redeemCreditService: PrivacyVoucherRedeemCreditServicing
    private let extrinsicOriginFactory: PersonhoodOriginFactoryProtocol
    private let logger: LoggerProtocol

    private let mutex = NSLock()

    init(
        chain: ChainModel,
        redeemCreditService: PrivacyVoucherRedeemCreditServicing,
        extrinsicOriginFactory: PersonhoodOriginFactoryProtocol,
        selectedWallet: WalletManaging = WalletManagerRepository.shared.mobRuleAlias(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.redeemCreditService = redeemCreditService
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.selectedWallet = selectedWallet
        self.logger = logger
    }
}

private extension MobRuleVoucherClaimService {
    func payoutCredits(_ mobCredits: MobRulePallet.MobCredit) {
        if mobCredits.credit > 0 {
            logger.debug("Non-zero mob rule credit: \(mobCredits.credit)")
        }

        redeemCreditService.redeemCredit(with: .init(
            credit: mobCredits.credit,
            voucherValue: .pathToFetch(MobRulePallet.voucherTypePath),
            originFactory: { [chain, selectedWallet, extrinsicOriginFactory] in
                try extrinsicOriginFactory.createAsPersonalAliasWithAccount(
                    input: .init(
                        wallet: selectedWallet,
                        chain: chain,
                        context: Data(PalletContext.mobRule.utf8),
                        blockHash: nil
                    )
                )
            },
            callFactory: { voucher in
                MobRulePallet.PayoutRewardsCall(
                    voucher: voucher.key.memberKey
                )
                .runtimeCall()
            }
        ))
    }
}

extension MobRuleVoucherClaimService: MobRuleVoucherClaimServicing {}
