package io.paritytech.polkadotapp.feature_become_citizen_api.domain.models

class TattooFamily(
    val kind: TattooFamilyKind,
    val id: ByteArray
)

sealed class TattooFamilyKind(val familyIndex: TattooFamilyIndex) {
    class Designed(index: TattooFamilyIndex, val count: Int) : TattooFamilyKind(index)
    class Procedural(index: TattooFamilyIndex, val range: Int) : TattooFamilyKind(index)
    class ProceduralAccount(index: TattooFamilyIndex) : TattooFamilyKind(index)
    class ProceduralPersonal(index: TattooFamilyIndex) : TattooFamilyKind(index)
}
