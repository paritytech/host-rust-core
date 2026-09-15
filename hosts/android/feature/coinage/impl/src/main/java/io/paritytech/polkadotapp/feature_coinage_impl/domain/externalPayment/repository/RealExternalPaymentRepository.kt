package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.repository

import com.google.gson.Gson
import io.paritytech.polkadotapp.chains.network.binding.intoBalance
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.database.dao.ExternalPaymentDao
import io.paritytech.polkadotapp.database.model.ExternalPaymentLocal
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RingVrfIndex
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.model.ExternalPayment
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class RealExternalPaymentRepository @Inject constructor(
    private val dao: ExternalPaymentDao,
    private val gson: Gson,
) : ExternalPaymentRepository {
    override suspend fun insert(payment: ExternalPayment) {
        dao.insert(payment.toLocal())
    }

    override suspend fun getNextPending(): ExternalPayment? =
        dao.getNextPending()?.toDomain()

    override fun observeById(id: PaymentId): Flow<ExternalPayment?> =
        dao.observeById(id).map { it?.toDomain() }

    private fun ExternalPaymentLocal.toDomain(): ExternalPayment {
        val surplus = surplusPlanks?.intoBalance()
        val selected = selectedVoucherKeys?.let(::deserializeKeys)
        val stage: ExternalPayment.Stage = when (stage) {
            ExternalPaymentLocal.Stage.ENSURE_VOUCHERS -> ExternalPayment.Stage.EnsureVouchers
            ExternalPaymentLocal.Stage.OFFBOARD_VOUCHERS -> ExternalPayment.Stage.OffboardVouchers(
                selectedVoucherKeys = requireNotNull(selected) { "OFFBOARD row missing selectedVoucherKeys" },
                surplus = requireNotNull(surplus) { "OFFBOARD row missing surplusPlanks" },
            )
            ExternalPaymentLocal.Stage.COMPLETED -> ExternalPayment.Stage.Completed
            ExternalPaymentLocal.Stage.PARTIALLY_COMPLETED ->
                ExternalPayment.Stage.PartiallyCompleted(failureReason.orEmpty())
            ExternalPaymentLocal.Stage.FAILED -> ExternalPayment.Stage.Failed(failureReason.orEmpty())
        }
        return ExternalPayment(
            id = id,
            origin = origin,
            amount = amountPlanks.intoBalance(),
            destination = destination.intoAccountId(),
            stage = stage,
            createdAt = createdAt,
            updatedAt = updatedAt,
        )
    }

    private fun ExternalPayment.toLocal(): ExternalPaymentLocal {
        val fields = stage.toRowFields()
        return ExternalPaymentLocal(
            id = id,
            origin = origin,
            amountPlanks = amount.value,
            destination = destination.value,
            stage = fields.stage,
            failureReason = fields.failureReason,
            selectedVoucherKeys = fields.selectedVoucherKeys,
            surplusPlanks = fields.surplusPlanks,
            createdAt = createdAt,
            updatedAt = updatedAt,
        )
    }

    private fun serializeKeys(keys: List<RingVrfIndex>): String = gson.toJson(keys)

    private fun deserializeKeys(json: String): List<RingVrfIndex> =
        gson.fromJson(json, IntArray::class.java).toList()

    private fun ExternalPayment.Stage.toRowFields(): RowStageFields = when (this) {
        ExternalPayment.Stage.EnsureVouchers -> RowStageFields(ExternalPaymentLocal.Stage.ENSURE_VOUCHERS)
        is ExternalPayment.Stage.OffboardVouchers -> RowStageFields(
            stage = ExternalPaymentLocal.Stage.OFFBOARD_VOUCHERS,
            selectedVoucherKeys = serializeKeys(selectedVoucherKeys),
            surplusPlanks = surplus.value,
        )
        ExternalPayment.Stage.Completed -> RowStageFields(ExternalPaymentLocal.Stage.COMPLETED)
        is ExternalPayment.Stage.PartiallyCompleted -> RowStageFields(
            stage = ExternalPaymentLocal.Stage.PARTIALLY_COMPLETED,
            failureReason = reason,
        )
        is ExternalPayment.Stage.Failed -> RowStageFields(
            stage = ExternalPaymentLocal.Stage.FAILED,
            failureReason = reason,
        )
    }
}

private data class RowStageFields(
    val stage: ExternalPaymentLocal.Stage,
    val selectedVoucherKeys: String? = null,
    val surplusPlanks: java.math.BigInteger? = null,
    val failureReason: String? = null,
)
