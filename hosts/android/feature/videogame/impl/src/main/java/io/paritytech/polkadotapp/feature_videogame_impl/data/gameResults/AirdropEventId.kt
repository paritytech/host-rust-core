package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.toBigEndianByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

/**
 * Storage key of a pallet-airdrop event: `"pop:game:airdrop:"` space-padded to 27 bytes,
 * followed by the airdrop index as a u8 and the game index as a big-endian u32 — mirrors
 * `Pallet::airdrop_event_id`. A game now schedules several airdrops; the app only registers
 * for the first one (index 0) for now, the rest are ignored.
 */
@JvmInline
value class AirdropEventId(val value: DataByteArray) {
    companion object {
        private const val PREFIX = "pop:game:airdrop:"
        private const val BASE_LENGTH = 27
        private const val SPACE = ' '.code.toByte()
        private const val FIRST_AIRDROP_INDEX: Byte = 0

        fun fromGameIndex(gameIndex: GameIndex): AirdropEventId {
            val prefix = PREFIX.toByteArray(Charsets.US_ASCII)
            val padded = prefix + ByteArray(BASE_LENGTH - prefix.size) { SPACE }
            val suffix = byteArrayOf(FIRST_AIRDROP_INDEX) + gameIndex.value.toBigEndianByteArray()
            return AirdropEventId((padded + suffix).toDataByteArray())
        }
    }
}
