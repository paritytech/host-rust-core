import TrUAPIHost

// The TrUAPIHost module is shadowed by its own `enum TrUAPIHost`, so
// `TrUAPIHost.Type` qualification never resolves. This file imports only
// TrUAPIHost, letting the bare names bind unambiguously; the aliases give
// files that also import Products/KeyDerivation collision-free names.
typealias TrUAPIHostProductAccountId = ProductAccountId
typealias TrUAPIHostDerivationIndex = DerivationIndex
typealias TrUAPIHostRawPayload = RawPayload
typealias TrUAPIHostAllocatableResource = AllocatableResource
typealias TrUAPIHostVrfTranscriptItem = VrfTranscriptItem
typealias TrUAPIHostSignVrfRequest = HostAccountSignVrfRequest
typealias TrUAPIHostRingLocation = RingLocation
