package io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.payoutRewards

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.orZero
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.logSuccess
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.MobRuleCreditsSyncWorker
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.credits
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRule
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRuleVoucherType
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.payoutRewards
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import io.paritytech.polkadotapp.feature_vouchers_api.data.VoucherRepository
import io.paritytech.polkadotapp.feature_vouchers_api.data.removeVouchers
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VoucherValueResolver
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherValue
import timber.log.Timber
import javax.inject.Inject

class RegisterMobRuleVouchersExecutor @Inject constructor(
    private val accountRepository: AccountRepository,
    private val privacyVoucherRepository: VoucherRepository,
    private val voucherValueResolverFactory: VoucherValueResolver.Factory,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val peopleOrigins: PeopleOrigins,
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
) : MobRuleCreditsSyncWorker.SyncExecutor {
    override suspend fun executeSync(): Result<Unit> {
        return getVouchersToIssue()
            .flatMap { numberOfVouchers -> issueVouchers(numberOfVouchers) }
    }

    private suspend fun getVouchersToIssue(): Result<Int> {
        return getVoucherValue().flatMap { voucherValue ->
            getMobRuleCredit().map { mobRuleCredit ->
                voucherValue.issuableVouchersFrom(mobRuleCredit)
            }
        }
    }

    private suspend fun getMobRuleCredit(): Result<Balance> {
        return storageDataSource.queryCatching(knownChains.people) {
            val alias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)
            metadata.mobRule.credits.query(alias)?.credit.orZero()
        }
    }

    private suspend fun getVoucherValue(): Result<VoucherValue> {
        return storageDataSource.queryCatching(knownChains.people) {
            metadata.mobRule.mobRuleVoucherType
        }.flatMap { voucherType ->
            voucherValueResolverFactory.foreground
                .resolveVoucherValue(voucherType)
        }
    }

    private suspend fun issueVouchers(numberOfVouchers: Int): Result<Unit> {
        if (numberOfVouchers == 0) {
            Timber.d("No vouchers to issue")

            return Result.success(Unit)
        }

        Timber.d("Issuing $numberOfVouchers vouchers")

        val chain = chainRegistry.getChain(knownChains.people)
        return peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.MOB_RULE).flatMap { transactionOrigin ->
            val metaId = accountRepository.getCandidateAccount().id
            val vouchers = (0..<numberOfVouchers).map {
                privacyVoucherRepository.generateNextVoucher(metaId, VoucherType.MOB_RULE_REWARD)
            }

            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = transactionOrigin,
            ) {
                vouchers.forEach { voucher ->
                    mobRule.payoutRewards(voucher)
                }
            }
                .flattenExecutionFailure()
                .coerceToUnit()
                .logFailure("Failed to issue $numberOfVouchers vouchers")
                .logSuccess("Successfully registered $numberOfVouchers vouchers")
                .onFailure { privacyVoucherRepository.removeVouchers(vouchers) }
        }
    }
}
