package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.extensions.toHexString
import io.paritytech.polkadotapp.common.domain.model.DataByteArray

/** A pallet-airdrop event key (`AirdropEventId.value` as a raw storage key). */
typealias AirdropEventKey = DataByteArray

/** A pallet-airdrop ticket slot (the per-registration key under an event). */
typealias TicketSlot = DataByteArray

/** A pallet-game attestation NFT hash (the deterministic `compute_nft` id). */
typealias AttestationNftHash = DataByteArray

/** The webview wire form: lowercase hex, no `0x` prefix. */
internal fun AttestationNftHash.hex(): String = value.toHexString(withPrefix = false)
