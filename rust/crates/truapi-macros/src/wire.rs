//! Wire-protocol metadata for TrUAPI methods.
//!
//! IDs and flags are emitted as hidden doc tags so they survive into rustdoc
//! JSON for `truapi-codegen`. Rust rejects unknown helper attributes on methods;
//! doc tags preserve the metadata without requiring such attributes.

use proc_macro::TokenStream;
use quote::quote;
use syn::parse::{Parse, ParseStream};
use syn::{Ident, ItemFn, LitInt, Token, TraitItemFn, parse_macro_input};

#[derive(Default)]
struct WireArgs {
    host_initiated: bool,
    request_id: Option<u8>,
    response_id: Option<u8>,
    start_id: Option<u8>,
    stop_id: Option<u8>,
    interrupt_id: Option<u8>,
    receive_id: Option<u8>,
    sensitive: bool,
}

impl Parse for WireArgs {
    fn parse(input: ParseStream<'_>) -> syn::Result<Self> {
        let mut args = WireArgs::default();

        while !input.is_empty() {
            let key: Ident = input.parse()?;

            if key == "host_initiated" {
                if args.host_initiated {
                    return Err(syn::Error::new(key.span(), "duplicate `host_initiated`"));
                }
                args.host_initiated = true;
            } else if key == "sensitive" {
                // `sensitive` is a bare flag with no `= N` value: it classifies
                // the method's payloads as carrying key material or bearer
                // secrets. The classification is folded into the wire
                // schema-hash fingerprint, so a change in a frame's sensitivity
                // is caught as contract drift. It suppresses no decoding: it
                // reaches neither the generated TS nor any runtime.
                if args.sensitive {
                    return Err(syn::Error::new(key.span(), "duplicate `sensitive`"));
                }
                args.sensitive = true;
            } else {
                input.parse::<Token![=]>()?;
                let lit: LitInt = input.parse()?;
                let value = lit.base10_parse().map_err(|err| {
                    syn::Error::new(lit.span(), format!("wire id must fit in a u8: {err}"))
                })?;

                set_id(&mut args, &key, value)?;
            }

            if input.is_empty() {
                break;
            }
            input.parse::<Token![,]>()?;
        }

        if args.request_id.is_none() && args.start_id.is_none() {
            return Err(input.error("missing `request_id = N` or `start_id = N`"));
        }

        Ok(args)
    }
}

fn set_id(args: &mut WireArgs, key: &Ident, value: u8) -> syn::Result<()> {
    let target = if key == "request_id" {
        &mut args.request_id
    } else if key == "response_id" {
        &mut args.response_id
    } else if key == "start_id" {
        &mut args.start_id
    } else if key == "stop_id" {
        &mut args.stop_id
    } else if key == "interrupt_id" {
        &mut args.interrupt_id
    } else if key == "receive_id" {
        &mut args.receive_id
    } else {
        return Err(syn::Error::new(
            key.span(),
            "expected one of `request_id`, `response_id`, `start_id`, `stop_id`, `interrupt_id`, `receive_id`, `host_initiated`, `sensitive`",
        ));
    };

    if target.replace(value).is_some() {
        return Err(syn::Error::new(key.span(), format!("duplicate `{key}`")));
    }

    Ok(())
}

/// Parse the macro input and emit generated code or a compiler diagnostic.
pub(super) fn expand(args: TokenStream, item: TokenStream) -> TokenStream {
    let args = parse_macro_input!(args as WireArgs);
    let tags = wire_tags(&args);

    if let Ok(mut method) = syn::parse::<TraitItemFn>(item.clone()) {
        for tag in tags {
            method.attrs.push(syn::parse_quote!(#[doc = #tag]));
        }
        return quote!(#method).into();
    }

    if let Ok(mut function) = syn::parse::<ItemFn>(item) {
        for tag in tags {
            function.attrs.push(syn::parse_quote!(#[doc = #tag]));
        }
        return quote!(#function).into();
    }

    syn::Error::new(
        proc_macro2::Span::call_site(),
        "#[wire] can only be applied to trait methods or free functions",
    )
    .to_compile_error()
    .into()
}

fn wire_tags(args: &WireArgs) -> Vec<String> {
    let mut tags: Vec<String> = [
        ("request_id", args.request_id),
        ("response_id", args.response_id),
        ("start_id", args.start_id),
        ("stop_id", args.stop_id),
        ("interrupt_id", args.interrupt_id),
        ("receive_id", args.receive_id),
    ]
    .into_iter()
    .filter_map(|(name, value)| value.map(|id| format!("@wire_{name}={id}")))
    .collect();
    if args.host_initiated {
        tags.push("@wire_host_initiated".to_string());
    }
    if args.sensitive {
        tags.push("@wire_sensitive=true".to_string());
    }
    tags
}
