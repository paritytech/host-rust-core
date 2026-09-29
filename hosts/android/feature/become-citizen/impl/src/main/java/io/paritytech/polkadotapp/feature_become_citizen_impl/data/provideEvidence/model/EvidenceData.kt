package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model

@JvmInline
value class RawEvidence(val value: ByteArray)

class RawEvidenceChunk(val value: ByteArray, val isLast: Boolean, val totalSize: Long)
