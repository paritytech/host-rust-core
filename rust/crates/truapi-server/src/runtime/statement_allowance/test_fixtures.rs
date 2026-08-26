//! Captured chain artefacts shared by the allowance unit tests: Asset Hub
//! metadata and one storage value read against it.

use std::sync::LazyLock;

use super::extension::Metadata;

/// `MembersSubscriber.RingRoots[(LitePeople, 5)]` captured alongside the
/// metadata, at block
/// `0xf25d4e330ade1ce230695976f019df50cdaf97c96b6996838af93b68550654f3`.
///
/// Ring 5 is the one whose window skips a revision, holding `[105, 106, 108]`
/// where every other lite-people ring is contiguous.
pub(crate) const ASSET_HUB_RING_5_ROOTS: &[u8] =
    include_bytes!("../../../tests/fixtures/paseo-next-asset-hub-ring-5-roots.scale");

/// Asset Hub metadata captured from paseo Asset Hub Next at spec 2000036.
///
/// The only fixture declaring `AsPgas`, `Pgas` and `MembersSubscriber`.
static ASSET_HUB: LazyLock<Metadata> = LazyLock::new(|| {
    Metadata::decode(include_bytes!(
        "../../../tests/fixtures/paseo-next-asset-hub-metadata.scale"
    ))
    .expect("the committed Asset Hub fixture decodes")
});

/// Borrow the decoded Asset Hub fixture.
pub(crate) fn asset_hub() -> &'static Metadata {
    &ASSET_HUB
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A truncated or mis-versioned capture would otherwise surface as a
    /// confusing decode failure inside an unrelated test.
    ///
    /// The roots length is pinned rather than checked for emptiness, so a
    /// re-capture has to re-confirm the record arithmetic.
    #[test]
    fn the_captured_asset_hub_artefacts_load() {
        assert_eq!(asset_hub().metadata_version(), 16);
        assert_eq!(
            ASSET_HUB_RING_5_ROOTS.len(),
            925,
            "3 records of 308 bytes plus a compact length prefix"
        );
    }
}
