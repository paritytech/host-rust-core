//! Emits `wire_table.rs`: the (trait, method) discriminant lookup table the
//! server uses to pair incoming wire frames with their request, response, or
//! subscription role.
//!
//! A trait-level `#[wire_trait(id = N)]` annotation assigns the trait
//! discriminant; per-method `#[wire(...)]` annotations decide method-id
//! assignment within the trait:
//! - request methods reserve `(request_id, response_id)`.
//! - subscription methods reserve `(start_id, stop_id, interrupt_id, receive_id)`.
//!
//! Missing annotations and collisions (per trait) both hard-fail codegen.

use std::collections::BTreeMap;
use std::fmt::Write;

use anyhow::{Result, bail};
use indoc::{formatdoc, writedoc};

use crate::rustdoc::*;

use super::{const_name, wire_method_name};

#[derive(Debug, Clone, Copy)]
struct WireEntry {
    trait_id: u8,
    request_id: u8,
    response_id: u8,
}

#[derive(Debug, Clone, Copy)]
struct SubEntry {
    trait_id: u8,
    start_id: u8,
    stop_id: u8,
    interrupt_id: u8,
    receive_id: u8,
}

#[derive(Debug, Clone, Copy)]
enum MethodEntry {
    Request(WireEntry),
    Subscription(SubEntry),
}

/// Emit the contents of `wire_table.rs`.
pub fn generate_wire_table(api: &ApiDefinition) -> Result<String> {
    let mut method_entries: Vec<(String, MethodEntry)> = Vec::new();
    let mut seen: BTreeMap<(u8, u8), String> = BTreeMap::new();
    let mut seen_traits: BTreeMap<u8, String> = BTreeMap::new();
    let mut seen_methods: BTreeMap<String, String> = BTreeMap::new();

    for trait_def in &api.traits {
        // Method-less traits (e.g. the `TrUApi` umbrella trait) own no wire
        // frames and need no trait discriminant.
        if trait_def.methods.is_empty() {
            continue;
        }
        let trait_id = trait_wire_id(trait_def)?;
        if let Some(existing) = seen_traits.insert(trait_id, trait_def.name.clone()) {
            bail!(
                "wire trait id {trait_id} reused: `{existing}` and `{}` collide",
                trait_def.name
            );
        }
        for method in &trait_def.methods {
            let entry = method_entry(trait_def, trait_id, method)?;
            let wire_method = wire_method_name(&trait_def.name, &method.name);
            if let Some(existing) = seen_methods.insert(
                wire_method.clone(),
                format!("{}::{}", trait_def.name, method.name),
            ) {
                bail!(
                    "wire method name `{wire_method}` reused: `{existing}` and `{}::{}` collide",
                    trait_def.name,
                    method.name
                );
            }
            insert_entry(&mut seen, &wire_method, entry)?;
            method_entries.push((wire_method, entry));
        }
    }

    method_entries.sort_by_key(|(_, entry)| match entry {
        MethodEntry::Request(WireEntry {
            trait_id,
            request_id,
            ..
        }) => (*trait_id, *request_id),
        MethodEntry::Subscription(SubEntry {
            trait_id, start_id, ..
        }) => (*trait_id, *start_id),
    });

    render(&method_entries)
}

/// The trait's wire discriminant. Every API trait must carry a
/// `#[wire_trait(id = N)]` annotation.
fn trait_wire_id(trait_def: &TraitDef) -> Result<u8> {
    trait_def.wire_trait_id.ok_or_else(|| {
        anyhow::anyhow!(
            "trait `{}` is missing #[wire_trait(id = N)] annotation",
            trait_def.name
        )
    })
}

fn method_entry(trait_def: &TraitDef, trait_id: u8, method: &MethodDef) -> Result<MethodEntry> {
    let wire = &method.wire;
    match method.kind {
        MethodKind::Request => {
            if wire.start_id.is_some()
                || wire.stop_id.is_some()
                || wire.interrupt_id.is_some()
                || wire.receive_id.is_some()
            {
                bail!(
                    "method `{}::{}` is a request and must not use subscription wire ids",
                    trait_def.name,
                    method.name
                );
            }
            let request_id = wire.request_id.ok_or_else(|| {
                anyhow::anyhow!(
                    "method `{}::{}` is missing #[wire(request_id = N)] annotation",
                    trait_def.name,
                    method.name
                )
            })?;
            let response_id = infer_id(wire.response_id, request_id, 1, &method.name)?;
            Ok(MethodEntry::Request(WireEntry {
                trait_id,
                request_id,
                response_id,
            }))
        }
        MethodKind::Subscription | MethodKind::ResultSubscription => {
            if wire.request_id.is_some() || wire.response_id.is_some() {
                bail!(
                    "method `{}::{}` is a subscription and must not use request wire ids",
                    trait_def.name,
                    method.name
                );
            }
            let start_id = wire.start_id.ok_or_else(|| {
                anyhow::anyhow!(
                    "method `{}::{}` is missing #[wire(start_id = N)] annotation",
                    trait_def.name,
                    method.name
                )
            })?;
            let stop_id = infer_id(wire.stop_id, start_id, 1, &method.name)?;
            let interrupt_id = infer_id(wire.interrupt_id, start_id, 2, &method.name)?;
            let receive_id = infer_id(wire.receive_id, start_id, 3, &method.name)?;
            Ok(MethodEntry::Subscription(SubEntry {
                trait_id,
                start_id,
                stop_id,
                interrupt_id,
                receive_id,
            }))
        }
    }
}

fn infer_id(explicit: Option<u8>, anchor: u8, offset: u8, method_name: &str) -> Result<u8> {
    if let Some(id) = explicit {
        return Ok(id);
    }
    anchor
        .checked_add(offset)
        .ok_or_else(|| anyhow::anyhow!("wire id overflow on `{method_name}` (base {anchor})"))
}

fn insert_entry(
    seen: &mut BTreeMap<(u8, u8), String>,
    method_name: &str,
    entry: MethodEntry,
) -> Result<()> {
    let pairs: Vec<(u8, u8, String)> = match entry {
        MethodEntry::Request(WireEntry {
            trait_id,
            request_id,
            response_id,
        }) => vec![
            (trait_id, request_id, format!("{method_name}_request")),
            (trait_id, response_id, format!("{method_name}_response")),
        ],
        MethodEntry::Subscription(SubEntry {
            trait_id,
            start_id,
            stop_id,
            interrupt_id,
            receive_id,
        }) => vec![
            (trait_id, start_id, format!("{method_name}_start")),
            (trait_id, stop_id, format!("{method_name}_stop")),
            (trait_id, interrupt_id, format!("{method_name}_interrupt")),
            (trait_id, receive_id, format!("{method_name}_receive")),
        ],
    };
    for (trait_id, id, tag) in pairs {
        if let Some(existing) = seen.insert((trait_id, id), tag.clone()) {
            bail!("wire id ({trait_id}, {id}) reused: `{existing}` and `{tag}` collide");
        }
    }
    Ok(())
}

fn render(methods: &[(String, MethodEntry)]) -> Result<String> {
    let mut out = String::new();
    writedoc!(
        out,
        r#"
        //! Wire-protocol discriminant table.
        //!
        //! Auto-generated by truapi-codegen. Do not edit.
        //!
        //! Every frame carries a `(trait, method)` discriminant pair. Each
        //! method reserves either two method ids (request/response) or four
        //! (start/stop/interrupt/receive) within its trait. The ids for each
        //! method are exposed as a named const (`PREIMAGE_SUBMIT`, ...);
        //! [`WIRE_TABLE`] and the generated dispatcher both reference those
        //! consts so the numbers live in exactly one place. The table is
        //! sorted by (trait id, request/start id).

        /// Request method wire discriminants.
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct RequestFrameIds {{
            /// Trait discriminant carried by both frames.
            pub trait_id: u8,
            /// Method discriminant for the request frame.
            pub request_id: u8,
            /// Method discriminant for the response frame.
            pub response_id: u8,
        }}

        /// Subscription method wire discriminants.
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct SubscriptionFrameIds {{
            /// Trait discriminant carried by all four frames.
            pub trait_id: u8,
            /// Method discriminant for the start frame.
            pub start_id: u8,
            /// Method discriminant for the stop frame.
            pub stop_id: u8,
            /// Method discriminant for the interrupt frame (server-initiated termination).
            pub interrupt_id: u8,
            /// Method discriminant for each receive frame (a streamed item).
            pub receive_id: u8,
        }}

        /// A single wire-table row.
        pub struct WireEntry {{
            /// Method name from the Rust trait.
            pub method: &'static str,
            /// What kind of slot this entry describes.
            pub kind: WireKind,
        }}

        /// Wire-slot shape: request/response pair or subscription quartet.
        pub enum WireKind {{
            /// Request/response method.
            Request(RequestFrameIds),
            /// Subscription method.
            Subscription(SubscriptionFrameIds),
        }}
        "#
    )
    .unwrap();

    // Per-method consts: the single source of truth for each method's ids.
    for (name, entry) in methods {
        let konst = const_name(name);
        let block = match entry {
            MethodEntry::Request(WireEntry {
                trait_id,
                request_id,
                response_id,
            }) => formatdoc! {
                r#"
                /// Wire discriminants for `{name}`.
                pub const {konst}: RequestFrameIds = RequestFrameIds {{
                    trait_id: {trait_id},
                    request_id: {request_id},
                    response_id: {response_id},
                }};
                "#
            },
            MethodEntry::Subscription(SubEntry {
                trait_id,
                start_id,
                stop_id,
                interrupt_id,
                receive_id,
            }) => formatdoc! {
                r#"
                /// Wire discriminants for `{name}`.
                pub const {konst}: SubscriptionFrameIds = SubscriptionFrameIds {{
                    trait_id: {trait_id},
                    start_id: {start_id},
                    stop_id: {stop_id},
                    interrupt_id: {interrupt_id},
                    receive_id: {receive_id},
                }};
                "#
            },
        };
        out.push('\n');
        out.push_str(&block);
    }

    out.push('\n');
    writedoc!(
        out,
        r#"
        /// The full wire table. Trait ids and per-trait method ordering are
        /// part of the wire protocol; only ever append within a trait.
        /// Removed methods leave their slot empty.
        pub const WIRE_TABLE: &[WireEntry] = &[
        "#
    )
    .unwrap();
    for (name, entry) in methods {
        let konst = const_name(name);
        let variant = match entry {
            MethodEntry::Request(_) => "Request",
            MethodEntry::Subscription(_) => "Subscription",
        };
        let block = formatdoc! {
            r#"
            WireEntry {{
                method: "{name}",
                kind: WireKind::{variant}({konst}),
            }},
            "#
        };
        for line in block.lines() {
            writeln!(out, "    {line}").unwrap();
        }
    }
    writeln!(out, "];").unwrap();

    Ok(out)
}
