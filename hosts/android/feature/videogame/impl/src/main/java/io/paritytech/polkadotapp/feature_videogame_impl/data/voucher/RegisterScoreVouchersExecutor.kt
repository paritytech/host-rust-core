package io.paritytech.polkadotapp.feature_videogame_impl.data.voucher

import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.intoSuccessResult
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.logSuccess
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionOrigin
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.AccountOrPersonData
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.map
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.origins.ScoreOrigins
import io.paritytech.polkadotapp.feature_videogame_impl.data.participants
import io.paritytech.polkadotapp.feature_videogame_impl.data.redeemCredit
import io.paritytech.polkadotapp.feature_videogame_impl.data.score
import io.paritytech.polkadotapp.feature_videogame_impl.data.voucherType
import io.paritytech.polkadotapp.feature_vouchers_api.data.VoucherRepository
import io.paritytech.polkadotapp.feature_vouchers_api.data.removeVouchers
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VoucherValueResolver
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherType
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherValue
import timber.log.Timber
import javax.inject.Inject

class RegisterScoreVouchersExecutor @Inject constructor(
    private val privacyVoucherRepository: VoucherRepository,
    private val accountRepository: AccountRepository,
    private val voucherValueResolverFactory: VoucherValueResolver.Factory,
    private val scoreOrigins: ScoreOrigins,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val peopleOrigins: PeopleOrigins,
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
    private val scoreContextProvider: ScoreContextProvider,
) : RegisterScoreVouchersWorker.SyncExecutor {
    override suspend fun executeSync(): Result<Unit> {
        return getVouchersToIssue()
            .flatMap { numberOfVouchers -> issueVouchers(numberOfVouchers) }
    }

    private suspend fun getVouchersToIssue(): Result<AccountOrPersonData<Int>?> {
        return getVoucherValue().flatMap { voucherValue ->
            getParticipantCredit().map { scoreCredit ->
                getIssuableVouchers(voucherValue, scoreCredit)
            }
        }
    }

    private fun getIssuableVouchers(
        voucherValue: VoucherValue,
        participantCredit: AccountOrPersonData<Balance>?
    ): AccountOrPersonData<Int>? {
        return participantCredit?.map { credit ->
            voucherValue.issuableVouchersFrom(credit)
                // TODO batches are not yet allowed when claiming the voucher. Claim once at a time
                .coerceAtMost(1)
        }
    }

    private suspend fun getParticipantCredit(): Result<AccountOrPersonData<Balance>?> {
        return storageDataSource.queryCatching(knownChains.people) {
            getAccountParticipantCredit() ?: getPersonParticipantCredit()
        }
    }

    context(storage: StorageQueryContext)
    private suspend fun getAccountParticipantCredit(): AccountOrPersonData<Balance>? {
        val candidateAccount = accountRepository.getCandidateAccount()
        val chain = chainRegistry.getChain(knownChains.people)
        val accountId = candidateAccount.accountIdIn(chain)
        val participant = OnChainAccountOrPerson.Account(accountId)

        return getParticipantCredit(participant)
            ?.let { AccountOrPersonData.fromAccount(it, accountId) }
    }

    context(storage: StorageQueryContext)
    private suspend fun getPersonParticipantCredit(): AccountOrPersonData<Balance>? {
        val candidateAccount = accountRepository.getCandidateAccount()
        val scoreAlias = bandersnatchSecretsStorage.getAliasInContext(candidateAccount.id, scoreContextProvider.context())
        val participant = OnChainAccountOrPerson.Person(scoreAlias)

        return getParticipantCredit(participant)
            ?.let { AccountOrPersonData.fromPerson(it, scoreAlias) }
    }

    context(storage: StorageQueryContext)
    private suspend fun getParticipantCredit(participant: OnChainAccountOrPerson): Balance? {
        val scoreParticipant = storage.metadata.score.participants.query(participant) ?: return null
        return scoreParticipant.credit
    }

    private suspend fun getVoucherValue(): Result<VoucherValue> {
        return storageDataSource.queryCatching(knownChains.people) {
            metadata.score.voucherType
        }.flatMap { voucherType ->
            voucherValueResolverFactory.foreground
                .resolveVoucherValue(voucherType)
        }
    }

    private suspend fun issueVouchers(numberOfVouchers: AccountOrPersonData<Int>?): Result<Unit> {
        if (numberOfVouchers == null || numberOfVouchers.data == 0) {
            Timber.d("No vouchers to issue")

            return Result.success(Unit)
        }

        Timber.d("Issuing ${numberOfVouchers.data} vouchers")

        val chain = chainRegistry.getChain(knownChains.people)
        return determineRegistrationOrigin(numberOfVouchers.key).flatMap { transactionOrigin ->
            val metaId = accountRepository.getCandidateAccount().id
            val vouchers = (0..<numberOfVouchers.data).map {
                privacyVoucherRepository.generateNextVoucher(metaId, VoucherType.SCORE)
            }

            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = transactionOrigin,
            ) {
                vouchers.forEach { voucher ->
                    score.redeemCredit(voucher)
                }
            }
                .flattenExecutionFailure()
                .coerceToUnit()
                .logFailure("Failed to issue ${numberOfVouchers.data} vouchers")
                .logSuccess("Successfully registered ${numberOfVouchers.data} vouchers")
                .onFailure { privacyVoucherRepository.removeVouchers(vouchers) }
        }
    }

    private suspend fun determineRegistrationOrigin(
        participantKey: OnChainAccountOrPerson
    ): Result<TransactionOrigin> {
        return when (participantKey) {
            is OnChainAccountOrPerson.Account -> {
                Timber.d("Using asAccountParticipant origin")

                scoreOrigins.asAccountParticipant()
                    .intoSuccessResult()
            }

            is OnChainAccountOrPerson.Person -> {
                Timber.d("Using score personal alias origin")

                peopleOrigins
                    .asPersonalAliasWithAccountEnsuringRevision(scoreContextProvider.context())
            }
        }
    }
}
