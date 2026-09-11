package io.paritytech.polkadotapp.feature_vouchers_impl.domain

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchDomainSize
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.createProof
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.logSuccess
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.onIndividualSuccess
import io.paritytech.polkadotapp.feature_transactions.api.data.requireAllIndividualSuccess
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherRingPosition
import io.paritytech.polkadotapp.feature_vouchers_api.domain.ClaimVouchersUseCase
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.Voucher
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherState
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.publicKey
import io.paritytech.polkadotapp.feature_vouchers_impl.data.PRIVACY_VOUCHER
import io.paritytech.polkadotapp.feature_vouchers_impl.data.VoucherInternalRepository
import io.paritytech.polkadotapp.feature_vouchers_impl.data.claimVoucherIntoDestination
import io.paritytech.polkadotapp.feature_vouchers_impl.data.privacyVoucher
import io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.origin.PrivacyVoucherOrigins
import timber.log.Timber

class RealClaimVoucherUseCase(
    private val chainRegistry: ChainRegistry,
    private val voucherRepository: VoucherInternalRepository,
    private val accountRepository: AccountRepository,
    private val extrinsicService: ExtrinsicService,
    private val voucherOrigins: PrivacyVoucherOrigins
) : ClaimVouchersUseCase {
    override suspend fun invoke(destination: AccountId, vouchers: List<Voucher>): Result<Unit> {
        val chain = chainRegistry.peopleChain()

        val claimableCandidates = vouchers.associateBy { it.publicKey() }

        Timber.d("Initiated claim of ${vouchers.size} candidates")

        return voucherRepository
            .getVoucherRingPositions(chain.id, claimableCandidates.keys)
            .mapCatching { voucherPositions -> groupVouchersByRing(chain, claimableCandidates, voucherPositions) }
            .flatMap { groups ->
                val claimerContext = BandersnatchContext.PRIVACY_VOUCHER
                val claimer = accountRepository.getAliasAccount(claimerContext).accountIdIn(chain)

                val claimableVouchers = groups.flatMap { it.vouchers }

                Timber.d("Claiming ${claimableVouchers.size} vouchers")

                val origin = voucherOrigins.voucherClaimer()

                extrinsicService.submitExtrinsicsAndAwaitInBlock(chain) {
                    groups.forEach { group ->
                        group.vouchers.forEach { voucher ->
                            extrinsic(origin = origin) {
                                val proof = voucher.entropy.createProof(
                                    allMembers = group.ringMembers,
                                    message = claimer.value,
                                    context = claimerContext.value,
                                    domainSize = BandersnatchDomainSize.Domain11
                                ).proof

                                privacyVoucher.claimVoucherIntoDestination(
                                    proof = proof.value,
                                    dest = destination,
                                    voucherValue = group.position.voucherValue,
                                    ringIndex = group.position.ringIndex
                                )
                            }
                        }
                    }
                }
                    .onIndividualSuccess { index, _ ->
                        val claimedVoucher = claimableVouchers[index]

                        voucherRepository.updateVoucherState(
                            index = claimedVoucher.index,
                            type = claimedVoucher.type,
                            newState = VoucherState.CLAIMED
                        )
                    }
                    .requireAllIndividualSuccess()
                    .logFailure("Failed to claim vouchers")
                    .logSuccess("Successfully claimed vouchers")
                    .coerceToUnit()
            }
    }

    private suspend fun groupVouchersByRing(
        chain: Chain,
        vouchersByKey: Map<BandersnatchPublicKey, Voucher>,
        voucherPositionsByKey: Map<BandersnatchPublicKey, PrivacyVoucherRingPosition>
    ): List<GroupedVouchers> {
        val keysByPosition = voucherPositionsByKey.entries.groupBy(
            keySelector = { it.value },
            valueTransform = { it.key }
        )

        val ringMembersByPosition = voucherRepository.getRingMembers(chain.id, keysByPosition.keys).getOrThrow()

        return keysByPosition.mapNotNull { (position, keys) ->
            val ringMembers = ringMembersByPosition[position] ?: return@mapNotNull null

            GroupedVouchers(
                ringMembers = ringMembers,
                position = position,
                vouchers = keys.mapNotNull { vouchersByKey[it] }
            )
        }
    }

    private class GroupedVouchers(
        val ringMembers: List<BandersnatchPublicKey>,
        val position: PrivacyVoucherRingPosition,
        val vouchers: List<Voucher>
    )
}
