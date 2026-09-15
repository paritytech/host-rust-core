package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment

import com.google.gson.Gson
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.chains.network.binding.intoBalance
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineLocalSession
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.database.dao.ExternalPaymentDao
import io.paritytech.polkadotapp.database.model.ExternalPaymentLocal
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RingVrfIndex
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.CompletedPaymentState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.EnsureVouchersPaymentState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.ExternalPaymentState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.FailedPaymentState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.OffboardVouchersPaymentState
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state.PartiallyCompletedPaymentState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class ExternalPaymentLocalSession @AssistedInject constructor(
    @Assisted private val paymentId: PaymentId,
    private val dao: ExternalPaymentDao,
    private val gson: Gson,
    private val ensureVouchersFactory: EnsureVouchersPaymentState.Factory,
    private val offboardVouchersFactory: OffboardVouchersPaymentState.Factory,
) : WorkerStateMachineLocalSession<ExternalPaymentState> {
    @AssistedFactory
    interface Factory {
        fun create(paymentId: PaymentId): ExternalPaymentLocalSession
    }

    override suspend fun getCurrentState(): ExternalPaymentState? =
        dao.getById(paymentId)?.toState()

    override suspend fun setCurrentState(state: ExternalPaymentState) {
        val stageEnum = state.stage()
        val (selected, surplus) = state.persistedPayload()
        val failureReason = (state as? FailedPaymentState)?.reason
            ?: (state as? PartiallyCompletedPaymentState)?.reason
        dao.updateStage(
            id = paymentId,
            stage = stageEnum,
            selectedVoucherKeys = selected?.let(::serializeKeys),
            surplusPlanks = surplus,
            failureReason = failureReason,
            updatedAt = System.currentTimeMillis(),
        )
    }

    override fun currentStateFlow(): Flow<ExternalPaymentState?> =
        dao.observeById(paymentId).map { it?.toState() }

    override suspend fun resetState() {
        // Terminal rows are intentionally kept (retention policy).
    }

    private fun ExternalPaymentLocal.toState(): ExternalPaymentState {
        val context = PaymentContext(
            id = id,
            origin = origin,
            amount = amountPlanks.intoBalance(),
            destination = destination.intoAccountId(),
        )
        return when (stage) {
            ExternalPaymentLocal.Stage.ENSURE_VOUCHERS -> ensureVouchersFactory.create(context)
            ExternalPaymentLocal.Stage.OFFBOARD_VOUCHERS -> offboardVouchersFactory.create(
                context = context,
                selected = deserializeKeys(
                    requireNotNull(selectedVoucherKeys) { "OFFBOARD row missing selectedVoucherKeys" }
                ),
                surplusPlanks = requireNotNull(surplusPlanks) { "OFFBOARD row missing surplusPlanks" },
            )
            ExternalPaymentLocal.Stage.COMPLETED -> CompletedPaymentState(context)
            ExternalPaymentLocal.Stage.PARTIALLY_COMPLETED ->
                PartiallyCompletedPaymentState(context, failureReason.orEmpty())
            ExternalPaymentLocal.Stage.FAILED -> FailedPaymentState(context, failureReason.orEmpty())
        }
    }

    private fun ExternalPaymentState.stage(): ExternalPaymentLocal.Stage = when (this) {
        is EnsureVouchersPaymentState -> ExternalPaymentLocal.Stage.ENSURE_VOUCHERS
        is OffboardVouchersPaymentState -> ExternalPaymentLocal.Stage.OFFBOARD_VOUCHERS
        is CompletedPaymentState -> ExternalPaymentLocal.Stage.COMPLETED
        is PartiallyCompletedPaymentState -> ExternalPaymentLocal.Stage.PARTIALLY_COMPLETED
        is FailedPaymentState -> ExternalPaymentLocal.Stage.FAILED
    }

    private fun ExternalPaymentState.persistedPayload(): Pair<List<RingVrfIndex>?, java.math.BigInteger?> = when (this) {
        is OffboardVouchersPaymentState -> selected to surplusPlanks

        is EnsureVouchersPaymentState,
        is CompletedPaymentState,
        is PartiallyCompletedPaymentState,
        is FailedPaymentState -> null to null
    }

    private fun serializeKeys(keys: List<RingVrfIndex>): String = gson.toJson(keys)

    private fun deserializeKeys(json: String): List<RingVrfIndex> =
        gson.fromJson(json, IntArray::class.java).toList()
}
