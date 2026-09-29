import Foundation
import Operation_iOS
import ExtrinsicService
import SubstrateSdk
import Individuality

protocol ReferralVoucherClaimServicing {
    func update(with person: ProofOfInkPallet.Person?)
}

final class ReferralVoucherClaimService {
    private let chain: ChainProtocol
    private let candidateWallet: MetaAccountModelProtocol
    private let redeemCreditService: PrivacyVoucherRedeemCreditServicing
    private let extrinsicOriginFactory: ExtrinsicOriginDefiningFactoryProtocol
    private let workQueue: DispatchQueue
    private let logger: LoggerProtocol

    private let mutex = NSLock()

    init(
        candidateWallet: MetaAccountModelProtocol,
        redeemCreditService: PrivacyVoucherRedeemCreditServicing,
        chain: ChainProtocol,
        extrinsicOriginFactory: ExtrinsicOriginDefiningFactoryProtocol, // AsPersonalIdentityWithAccountOriginFactory
        workQueue: DispatchQueue = .global(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.candidateWallet = candidateWallet
        self.redeemCreditService = redeemCreditService
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.workQueue = workQueue
        self.logger = logger
    }
}

extension ReferralVoucherClaimService: ReferralVoucherClaimServicing {
    func update(with person: ProofOfInkPallet.Person?) {
        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            mutex.lock()

            defer {
                mutex.unlock()
            }

            if let referralRewardCount = person?.pendingReferralRewards {
                redeemVouchers(referralRewardCount)
            }
        }
    }
}

private extension ReferralVoucherClaimService {
    func redeemVouchers(_ referralRewardCount: UInt32) {
        guard referralRewardCount > 0 else {
            return
        }

        logger.debug("Non-zero referral vouchers: \(referralRewardCount)")

        redeemCreditService.redeemCredit(with: .init(
            credit: Balance(referralRewardCount),
            voucherValue: .hardcoded(1),
            originFactory: { [weak self] in
                guard let self else {
                    throw BaseOperationError.unexpectedDependentResult
                }
                // was createAsPersonalIdentityWithAccount
                return try extrinsicOriginFactory.extrinsicOriginDefiner(
                    from: candidateWallet,
                    chain: chain
                )
            },
            callFactory: { voucher in
                ProofOfInkPallet.RegisterReferralVouchers(
                    voucherKey: voucher.key.memberKey
                )
                .runtimeCall()
            }
        ))
    }
}
