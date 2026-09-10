@file:OptIn(ExperimentalUnsignedTypes::class)

package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decoder.ScaleDecoder
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.encoder.ScaleEncoder
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

@Serializable(ProceduralSeedSerializer::class)
sealed class ProceduralSeed {
    abstract fun getBytes(): UByteArray
    abstract fun getUniqueSeedKey(): String

    data class Raw(val entropy: DataByteArray, val index: Int) : ProceduralSeed() {
        override fun getBytes(): UByteArray {
            val entropyArray = entropy.value

            return ByteArray(4).apply {
                if (index < 8) {
                    entropyArray.copyInto(this, 0, index * 4, index * 4 + 4)
                } else {
                    var id = index
                    val index = IntArray(4)
                    for (i in 0 until 4) {
                        val range = 32 - i
                        index[i] = id % range
                        for (o in 0 until i) {
                            if (index[i] >= index[o]) {
                                index[i] += 1
                            }
                        }
                        this[i] = entropyArray[index[i]]
                        id /= range
                    }
                }
            }.toUByteArray()
        }

        override fun getUniqueSeedKey() = "${entropy.value.contentHashCode()}_$index"
    }

    data class Final(val seed: DataByteArray) : ProceduralSeed() {
        override fun getBytes() = seed.value.toUByteArray()

        override fun getUniqueSeedKey() = seed.value.contentHashCode().toString()
    }
}

/**
 * We want to represent ProceduralSeed as InkChoice associated value for encoding and InkSpec associated value for decoding
 */
class ProceduralSeedSerializer : KSerializer<ProceduralSeed> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("ProceduralSeed", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): ProceduralSeed {
        require(decoder is ScaleDecoder)

        val seed = decoder.decodeByteArray().toDataByteArray()

        return ProceduralSeed.Final(seed)
    }

    override fun serialize(encoder: Encoder, value: ProceduralSeed) {
        require(encoder is ScaleEncoder)

        return when (value) {
            is ProceduralSeed.Final -> encoder.encodeByteArray(value.seed.value)
            is ProceduralSeed.Raw -> encoder.encodeInt(value.index)
        }
    }
}
