//! Root product manifest parsing and grant lookup.
//!
//! Pure: the bytes arrive from [`crate::runtime::product_manifest`], and nothing
//! here reaches a chain. A manifest carries more than the trust grants, but only
//! the fields this core reads are modelled — everything else is skipped, so a
//! publisher extending the document does not break parsing.

use std::collections::BTreeMap;

use serde::Deserialize;

/// Manifest schema version this core parses.
const SUPPORTED_SCHEMA_VERSION: u32 = 1;

/// A scope a publisher pre-approves for another product in `trustedProducts`.
///
/// `All` is a superset rather than a peer: it satisfies every other variant,
/// present and future. A value this core does not recognise parses as
/// [`Granted::Unrecognised`] rather than failing the document.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Granted {
    /// Every mediated interaction, present and future.
    All,
    /// Reading the granting product's host-local storage.
    Storage,
    /// Using the granting product's account and the identity behind it.
    Context,
    /// A grant value defined after this core was built.
    Unrecognised,
}

impl<'de> Deserialize<'de> for Granted {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(match String::deserialize(deserializer)?.as_str() {
            "all" => Self::All,
            "storage" => Self::Storage,
            "context" => Self::Context,
            _ => Self::Unrecognised,
        })
    }
}

/// The product-wide manifest published at a base name's `manifest` text record.
#[derive(Debug, Clone, Deserialize)]
pub struct RootManifest {
    /// Schema version. A version this core does not know makes the product
    /// undiscoverable rather than malformed.
    #[serde(rename = "$v")]
    pub schema_version: u32,
    /// What each named product may do to this one, keyed by bare product label
    /// with no TLD suffix.
    #[serde(default, rename = "trustedProducts")]
    pub trusted_products: BTreeMap<String, Vec<Granted>>,
}

impl RootManifest {
    /// Parses a manifest, rejecting a schema version this core cannot read.
    ///
    /// An unrecognised grant value is not a parse failure: it is dropped from
    /// the entry it appears in and the recognised values around it still apply.
    pub fn parse(json: &str) -> Result<Self, String> {
        let manifest: Self = serde_json::from_str(json)
            .map_err(|err| format!("manifest is not valid JSON: {err}"))?;
        if manifest.schema_version != SUPPORTED_SCHEMA_VERSION {
            return Err(format!(
                "manifest schema version {} is not supported",
                manifest.schema_version
            ));
        }
        Ok(manifest)
    }

    /// Whether this product grants `caller` the `wanted` scope.
    ///
    /// `caller` is a bare product label with no TLD suffix, matching the shape
    /// of a `trustedProducts` key. A key written with a suffix names a product
    /// that does not resolve, so it grants nothing.
    pub fn grants(&self, caller: &str, wanted: Granted) -> bool {
        self.trusted_products.get(caller).is_some_and(|granted| {
            granted
                .iter()
                .any(|value| *value == Granted::All || *value == wanted)
        })
    }
}

/// Strips the TLD from a normalized product identifier, yielding the bare label
/// a `trustedProducts` key is written with.
///
/// A localhost development identifier has no TLD and is returned unchanged.
pub fn bare_product_label(product_id: &str) -> &str {
    product_id
        .split_once('.')
        .map_or(product_id, |(label, _)| label)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(trusted: &str) -> RootManifest {
        RootManifest::parse(&format!(
            r#"{{"$v":1,"displayName":"D","description":"d",
                "icon":{{"cid":"c","format":"png"}},"trustedProducts":{trusted}}}"#
        ))
        .expect("fixture parses")
    }

    #[test]
    fn a_named_scope_is_granted_only_to_the_product_named() {
        let m = manifest(r#"{"dim2":["storage"]}"#);
        assert!(m.grants("dim2", Granted::Storage));
        assert!(!m.grants("stash", Granted::Storage));
    }

    #[test]
    fn scopes_are_independent() {
        // `storage` must leave account interactions prompting as usual.
        let m = manifest(r#"{"dim2":["storage"]}"#);
        assert!(!m.grants("dim2", Granted::Context));
    }

    #[test]
    fn all_satisfies_every_narrower_scope() {
        let m = manifest(r#"{"dim2":["all"]}"#);
        assert!(m.grants("dim2", Granted::Storage));
        assert!(m.grants("dim2", Granted::Context));
    }

    #[test]
    fn an_unrecognised_grant_is_ignored_and_its_neighbours_still_apply() {
        // The RFC forbids failing validation over a value defined after this
        // core was built.
        let m = manifest(r#"{"dim2":["storage-write","storage"]}"#);
        assert!(m.grants("dim2", Granted::Storage));
        assert!(!m.grants("dim2", Granted::Context));
    }

    #[test]
    fn an_entry_of_only_unrecognised_grants_grants_nothing() {
        let m = manifest(r#"{"dim2":["storage-write"]}"#);
        assert!(!m.grants("dim2", Granted::Storage));
        assert!(!m.grants("dim2", Granted::Context));
    }

    #[test]
    fn a_key_written_with_a_tld_suffix_is_inert() {
        // It names `dim2.dot.<tld>`, which does not exist, so the caller `dim2`
        // matches nothing.
        let m = manifest(r#"{"dim2.dot":["storage"]}"#);
        assert!(!m.grants("dim2", Granted::Storage));
    }

    #[test]
    fn an_absent_trusted_products_field_grants_nothing() {
        let m = RootManifest::parse(
            r#"{"$v":1,"displayName":"D","description":"d","icon":{"cid":"c","format":"png"}}"#,
        )
        .expect("manifest without trustedProducts parses");
        assert!(!m.grants("dim2", Granted::Storage));
    }

    #[test]
    fn an_unknown_schema_version_is_refused() {
        assert!(RootManifest::parse(r#"{"$v":2,"trustedProducts":{}}"#).is_err());
    }

    #[test]
    fn malformed_json_is_refused() {
        assert!(RootManifest::parse("not json").is_err());
    }

    #[test]
    fn the_bare_label_drops_the_tld() {
        assert_eq!(bare_product_label("dim2.dot"), "dim2");
        assert_eq!(bare_product_label("dim2.paseo"), "dim2");
        assert_eq!(bare_product_label("localhost"), "localhost");
    }
}
