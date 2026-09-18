//! Allowance-facing view of a personhood ring collection.
//!
//! A person can hold membership in more than one collection, and each one is a
//! separate alias space with its own slot budget: aliases are derived from
//! collection-specific entropy, so the same `(period, seq)` in two collections
//! is two distinct storage entries. Capacity is therefore the sum over the
//! collections a device can prove membership in, which is why the allowance
//! path takes a collection rather than assuming one.
//!
//! The type itself lives in [`crate::host_logic::product_account`], which is
//! compiled for wasm32 as this module is not, and which owns the member-key
//! derivation. What stays here is what only the allowance path asks of it: the
//! chain metadata naming its slot budget.

use super::StatementAllowanceError;
use super::extension::Metadata;
use super::rpc::RpcClient;
use super::view;

pub use crate::host_logic::product_account::PersonhoodCollection;

impl PersonhoodCollection {
    /// The `Resources` view function returning StatementStore slots per period
    /// for this collection.
    pub fn slots_per_period_view(self) -> &'static str {
        match self {
            Self::People => "get_stmt_store_slots_per_period",
            Self::LitePeople => "get_lite_stmt_store_slots_per_period",
        }
    }

    /// The `Pgas` constant bounding claims per period for this collection.
    pub fn pgas_claims_per_period_constant(self) -> &'static str {
        match self {
            Self::People => "MaxClaimsPerPeriodPerPerson",
            Self::LitePeople => "MaxClaimsPerPeriodPerLitePerson",
        }
    }

    /// Whether this chain exposes a StatementStore slot budget for this collection.
    pub fn is_supported(self, metadata: &Metadata) -> bool {
        view::supports_resource_u32(metadata, self.slots_per_period_view())
    }

    /// Max StatementStore slots per period for this collection.
    pub async fn slots_per_period(
        self,
        rpc: &RpcClient,
        metadata: &Metadata,
    ) -> Result<u32, StatementAllowanceError> {
        view::read_resource_u32(rpc, metadata, self.slots_per_period_view()).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn people_is_offered_before_lite_people() {
        // Callers stop at the first collection that yields a slot, so ordering
        // is what makes a full person spend their wider budget first.
        assert_eq!(
            PersonhoodCollection::ALL,
            [
                PersonhoodCollection::People,
                PersonhoodCollection::LitePeople
            ],
        );
    }

    #[test]
    fn each_collection_names_its_own_pgas_claim_constant() {
        // Asset Hub declares a separate claim budget per collection, so a full
        // person must not be scanned against the light one's share.
        assert_eq!(
            PersonhoodCollection::People.pgas_claims_per_period_constant(),
            "MaxClaimsPerPeriodPerPerson",
        );
        assert_eq!(
            PersonhoodCollection::LitePeople.pgas_claims_per_period_constant(),
            "MaxClaimsPerPeriodPerLitePerson",
        );
        assert_ne!(
            PersonhoodCollection::People.pgas_claims_per_period_constant(),
            PersonhoodCollection::LitePeople.pgas_claims_per_period_constant(),
        );
    }

    #[test]
    fn each_collection_names_its_own_variant_and_slot_view() {
        assert_eq!(PersonhoodCollection::People.metadata_variant(), "People");
        assert_eq!(
            PersonhoodCollection::LitePeople.metadata_variant(),
            "LitePeople"
        );
        assert_eq!(
            PersonhoodCollection::People.slots_per_period_view(),
            "get_stmt_store_slots_per_period",
        );
        assert_eq!(
            PersonhoodCollection::LitePeople.slots_per_period_view(),
            "get_lite_stmt_store_slots_per_period",
        );
    }
}
