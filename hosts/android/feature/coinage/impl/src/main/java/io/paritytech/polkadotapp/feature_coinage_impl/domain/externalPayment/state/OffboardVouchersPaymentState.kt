package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.chains.network.binding.intoBalance
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState.TransitionResult
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RingVrfIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageOperationGroupId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.usecase.ExternalUnloadStatus
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.usecase.UnloadRecyclerIntoExternalAssetUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.CoinageAssetSelector
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.SpendScope
import kotlinx.coroutines.flow.first
import java.math.BigInteger

/**
 * Offboards a selected subset of recycler vouchers straight into the destination account's
 * external-asset balance. When `surplusPlanks` is positive, the surplus is folded back into
 * freshly-minted vouchers inside the same call via
 * Coinage.unload_recycler_into_external_asset_and_loaded_coins; otherwise
 * Coinage.unload_recycler_into_external_asset is used.
 */
class OffboardVouchersPaymentState @AssistedInject constructor(
    @Assisted override val context: PaymentContext,
    @Assisted val selected: List<RingVrfIndex>,
    @Assisted val surplusPlanks: BigInteger,
    private val assetSelector: CoinageAssetSelector,
    private val unloadIntoExternalAsset: UnloadRecyclerIntoExternalAssetUseCase,
    private val ensureVouchersFactory: EnsureVouchersPaymentState.Factory,
) : ExternalPaymentState {
    override val id: String = "OffboardVouchers"

    val surplus: Balance get() = surplusPlanks.intoBalance()

    @AssistedFactory
    interface Factory {
        fun create(
            context: PaymentContext,
            selected: List<RingVrfIndex>,
            surplusPlanks: BigInteger,
        ): OffboardVouchersPaymentState
    }

    context(noContext: NoContext)
    override suspend fun performTransition(): TransitionResult<ExternalPaymentState> = runTransition {
        // Selectable, not merely on chain: a voucher another operation of ours already holds would be
        // rejected at registration and take the whole unload down with it.
        val selectableByIndex = assetSelector.getSelectableVouchers(SpendScope.SPENDABLE).associateBy { it.ringVrfKeyIndex }
        val vouchers = selected.mapNotNull { selectableByIndex[it] }

        if (vouchers.size != selected.size) {
            // A stale plan, not a failed payment: the money is still there, so plan again rather than
            // telling the caller it lost.
            return@runTransition ensureVouchersFactory.create(context)
        }

        val groupId = unloadGroupOf(context.id)

        unloadIntoExternalAsset.initiateUnload(
            vouchers = vouchers,
            destination = context.destination,
            surplus = surplus,
            groupId = groupId,
        ).getOrThrow()

        // Continues in this tick rather than leaving the outcome to a worker retry: the payment is not
        // delivered until the chain says so, and the caller is waiting on this transition to find out.
        awaitOutcome(groupId)
    }

    private suspend fun awaitOutcome(groupId: CoinageOperationGroupId): ExternalPaymentState {
        val outcome = unloadIntoExternalAsset.subscribeUnloadStatus(groupId)
            .first { it !is ExternalUnloadStatus.Submitted }

        return when (outcome) {
            is ExternalUnloadStatus.Success -> CompletedPaymentState(context)

            is ExternalUnloadStatus.PartialSuccess -> PartiallyCompletedPaymentState(
                context = context,
                reason = "${outcome.executed} of ${outcome.total} unload transactions executed",
            )

            is ExternalUnloadStatus.Failed -> FailedPaymentState(context, "no unload transaction executed")

            is ExternalUnloadStatus.Submitted -> error("Unreachable: filtered out above")
        }
    }
}

/**
 * The payment's own id, so the group is found again after a crash without anything extra being persisted for
 * it. Re-entering this state then joins the transactions the previous attempt registered instead of unloading
 * the same vouchers twice.
 */
private fun unloadGroupOf(paymentId: PaymentId) = CoinageOperationGroupId("external-payment:$paymentId")
