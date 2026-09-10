package io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.BinaryScale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.decodeFromByteArray
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.encodeToByteArray
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.serialization.Serializable

/**
 * Recorded in a tracked tx's `additional` and decoded by the override interceptor. [playerStorageKey] is the
 * `VideoGame.Players` storage key of the player this tx affects (matched verbatim against the read-time key);
 * [gameIndex] lets the interceptor synthesize a player row when the chain has none yet.
 */
@Serializable
class VideoGamePlayerOverrideTarget(
    val playerStorageKey: String,
    val gameIndex: GameIndex,
)

fun VideoGamePlayerOverrideTarget.encodeToAdditional(): DataByteArray =
    BinaryScale.encodeToByteArray(this).toDataByteArray()

fun DataByteArray.decodeOverrideTargetOrNull(): VideoGamePlayerOverrideTarget? =
    runCatching { BinaryScale.decodeFromByteArray<VideoGamePlayerOverrideTarget>(value) }.getOrNull()
