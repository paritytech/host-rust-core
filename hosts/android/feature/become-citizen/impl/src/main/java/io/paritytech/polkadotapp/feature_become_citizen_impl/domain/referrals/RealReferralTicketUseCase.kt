package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.unwrapResultOrDefault
import io.paritytech.polkadotapp.common.utils.wrapIntoResult
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.proofOfInk
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.calls.setReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.toDomain
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.ProofOfInkReferralsRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.ReferralTicketUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketAvailability
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketDeeplink
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketOrigin
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.models.ReferralTicketPublic
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import javax.inject.Inject

internal class RealReferralTicketUseCase @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val proofOfInkReferralsRepository: ProofOfInkReferralsRepository,
    private val extrinsicService: ExtrinsicService,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val referralTicketDeeplinkMapper: ReferralTicketDeeplinkMapper,
    private val peopleOrigins: PeopleOrigins,
) : ReferralTicketUseCase {
    override fun referralTicketAvailabilityFlow(): Flow<ReferralTicketAvailability> {
        return tattooProgressStateUseCase.tattooProgressStateFlow()
            .unwrapResultOrDefault(TattooProgressState.Unknown)
            .flatMapLatest { tattooProgress: TattooProgressState ->
                if (tattooProgress is TattooProgressState.RecognizedPerson) {
                    observeReferralTicketAvailability(tattooProgress)
                } else {
                    flowOf(ReferralTicketAvailability.NotAvailable)
                }
            }
    }

    private suspend fun observeReferralTicketAvailability(
        tattooRecognizedPerson: TattooProgressState.RecognizedPerson
    ): Flow<ReferralTicketAvailability> {
        val chain = chainRegistry.peopleChain()

        val maxActiveReferrals = proofOfInkReferralsRepository.getMaxActiveReferrals(chain.id)
            .getOrDefault(1)

        val personId = tattooRecognizedPerson.personId

        return combine(
            proofOfInkReferralsRepository.referralTicketsFlow(chain.id, personId),
            proofOfInkReferralsRepository.subscribeSavedTicket(ReferralTicketOrigin.REFERRER)
        ) { onChainRegisteredTickets, locallySavedTicket ->
            val referrerState = ReferrerOnChainState(
                recognizedState = tattooRecognizedPerson,
                registeredTickets = onChainRegisteredTickets.map { it.toDomain() },
                maxMaxActiveReferrals = maxActiveReferrals
            )

            when {
                locallySavedTicket != null && referrerState.canReuseExistingTicket(
                    locallySavedTicket.toPublic()
                ) -> ReferralTicketAvailability.Available(
                    referrer = personId,
                    existingTicket = locallySavedTicket
                )

                else -> when (referrerState.canGenerateNewTicket()) {
                    GenerateNewTicketState.CAN_GENERATE -> ReferralTicketAvailability.Available(
                        referrer = personId,
                        existingTicket = null
                    )

                    GenerateNewTicketState.LIMIT_REACHED -> ReferralTicketAvailability.ActiveReferralsLimitReached
                    GenerateNewTicketState.NOT_AVAILABLE -> ReferralTicketAvailability.NotAvailable
                }
            }
        }
            .wrapIntoResult()
            .logFailure("Failed to determine referral ticket availability")
            .map { it.getOrDefault(ReferralTicketAvailability.NotAvailable) }
    }

    override suspend fun generateReferralTicket(availability: ReferralTicketAvailability.Available): Result<ReferralTicketDeeplink> {
        return withContext(coroutineDispatchers.io) {
            val chain = chainRegistry.peopleChain()

            val existing = availability.existingTicket
            if (existing != null) {
                return@withContext Result.success(referralTicketDeeplinkMapper.toDeeplink(existing))
            }

            val newTicket = ReferralTicket.generateNew(availability.referrer)

            // Save new ticket in advance, so we wont loose it in case some connection issue occurs later on but tx would actually been successful
            saveLocalTicket(newTicket)

            extrinsicService.submitExtrinsicAndAwaitExecution(
                chain = chain,
                origin = peopleOrigins.asPersonalIdentityWithAccount()
            ) {
                proofOfInk.setReferralTicket(newTicket.toPublic())
            }
                .flattenExecutionFailure()
                .mapCatching {
                    referralTicketDeeplinkMapper.toDeeplink(newTicket)
                }
        }
    }

    private suspend fun saveLocalTicket(ticket: ReferralTicket) {
        proofOfInkReferralsRepository.saveTicket(ReferralTicketOrigin.REFERRER, ticket)
    }

    private class ReferrerOnChainState(
        val recognizedState: TattooProgressState.RecognizedPerson,
        val registeredTickets: List<ReferralTicketPublic>,
        val maxMaxActiveReferrals: Int
    ) {
        fun canGenerateNewTicket(): GenerateNewTicketState {
            return when {
                // TODO we can auto-claim referral rewards before generating a new one instead of just disabling option to generate a ticket
                recognizedState.banned || recognizedState.pendingReferralRewards > 0 -> GenerateNewTicketState.NOT_AVAILABLE

                recognizedState.activeReferrals.size >= maxMaxActiveReferrals -> GenerateNewTicketState.LIMIT_REACHED

                registeredTickets.size >= recognizedState.allowedReferralTickets -> GenerateNewTicketState.LIMIT_REACHED

                else -> GenerateNewTicketState.CAN_GENERATE
            }
        }

        fun canReuseExistingTicket(ticket: ReferralTicketPublic): Boolean {
            if (recognizedState.banned) return false

            return registeredTickets.any { it == ticket }
        }
    }

    enum class GenerateNewTicketState {
        CAN_GENERATE, LIMIT_REACHED, NOT_AVAILABLE
    }
}
