//! Emits `dispatcher.rs`: the server-side wire dispatcher that routes
//! incoming frames to the host trait implementation.
//!
//! For each method the emitter produces an `on_request` (or
//! `on_subscription`) registration that:
//! 1. SCALE-decodes the versioned request wrapper directly from the wire
//!    bytes (the wrapper's own variant tag carries its version — there is no
//!    outer envelope).
//! 2. Calls the host trait method (which receives the wrapper directly
//!    and matches `_::V1(inner)` internally).
//! 3. SCALE-encodes the versioned response wrapper back onto the wire.
//!
//! Which leg of the exchange a frame carries (request/response, or a
//! subscription's start/receive/interrupt/stop) is the outer wire's own
//! `message_type` byte, addressed alongside `(trait, method)` by the
//! framework — this module never encodes or matches on it.
//!
//! The generated file expects to live inside a `truapi-server` crate
//! and references `crate::dispatcher::Dispatcher`. The codegen itself
//! does not compile the output; string-diff golden tests guard it.

use std::collections::BTreeMap;
use std::collections::BTreeSet;
use std::fmt::Write;

use anyhow::{Result, bail};
use indoc::{formatdoc, indoc, writedoc};

use crate::rustdoc::*;

use super::{const_name, module_for_trait, wire_method_name};

/// Emit the contents of `dispatcher.rs`.
pub fn generate_dispatcher(api: &ApiDefinition) -> Result<String> {
    let traits = order_traits(api)?;

    // Reject any duplicate wire method name across traits before emission, so
    // a future addition can't silently overwrite a handler in the HashMap.
    let mut seen: BTreeSet<String> = BTreeSet::new();
    for trait_def in &traits {
        for method in &trait_def.methods {
            let key = wire_method_name(&trait_def.name, &method.name);
            if !seen.insert(key.clone()) {
                bail!(
                    "Wire method name `{key}` registered twice; \
                     change `{}::{}` or its sibling trait to disambiguate",
                    trait_def.name,
                    method.name
                );
            }
        }
    }

    let mut modules = Vec::with_capacity(traits.len());
    for trait_def in &traits {
        modules.push(build_module(api, trait_def)?);
    }

    let mut out = String::new();
    write_header(&mut out);
    write_imports(&mut out, &traits);
    writeln!(out).unwrap();
    write_top_register(&mut out, &traits);
    write_host_initiated_callers(&mut out, api, &traits)?;

    for module in &modules {
        writeln!(out).unwrap();
        out.push_str(module);
    }

    Ok(out)
}

/// Returns the traits to emit, in the order declared by the top-level
/// `TrUApi` super-trait. Falls back to alphabetical order if the
/// extractor did not record a public ordering (e.g. synthetic tests).
fn order_traits(api: &ApiDefinition) -> Result<Vec<&TraitDef>> {
    let by_name: BTreeMap<&str, &TraitDef> =
        api.traits.iter().map(|t| (t.name.as_str(), t)).collect();

    if api.public_trait_order.is_empty() {
        return Ok(api.traits.iter().collect());
    }

    let mut ordered = Vec::with_capacity(api.public_trait_order.len());
    for name in &api.public_trait_order {
        let Some(trait_def) = by_name.get(name.as_str()) else {
            bail!("trait `{name}` appears in TrUApi but was not extracted");
        };
        ordered.push(*trait_def);
    }
    Ok(ordered)
}

/// Emit the `register_{module}` function for a single trait.
fn build_module(api: &ApiDefinition, trait_def: &TraitDef) -> Result<String> {
    let module = module_for_trait(&trait_def.name);

    let mut methods = Vec::with_capacity(trait_def.methods.len());
    for method in trait_def
        .methods
        .iter()
        .filter(|method| !method.wire.host_initiated)
    {
        let wire_method = wire_method_name(&trait_def.name, &method.name);
        methods.push(MethodEmission::build(
            api,
            &module,
            &wire_method,
            method,
            trait_def.required_execution(),
        )?);
    }

    let fn_name = format!("register_{module}");
    let trait_name = &trait_def.name;
    let mut code = String::new();
    writedoc!(
        code,
        r#"
        fn {fn_name}<P>(dispatcher: &mut Dispatcher, host: Arc<P>)
        where
            P: {trait_name} + Send + Sync + 'static,
        {{
        "#
    )
    .unwrap();
    let last = methods.len().saturating_sub(1);
    for (idx, method) in methods.iter().enumerate() {
        let host_expr = if idx == last { "host" } else { "host.clone()" };
        method.write(&mut code, host_expr)?;
    }
    writeln!(code, "}}").unwrap();

    Ok(code)
}

/// Emit the free functions that start a host-initiated subscription (a
/// method the host calls into the product, e.g.
/// `chat_custom_message_render`). Its `Start` payload is the request
/// wrapper's own encoding, sent immediately rather than registered against
/// the dispatcher; the product's `Receive`/`Interrupt` replies are routed
/// back by [`HostInitiatedSubscriptionManager`].
fn write_host_initiated_callers(
    out: &mut String,
    api: &ApiDefinition,
    traits: &[&TraitDef],
) -> Result<()> {
    let wrappers = versioned_wrapper_names(api);
    for trait_def in traits {
        let module = module_for_trait(&trait_def.name);
        for method in trait_def
            .methods
            .iter()
            .filter(|method| method.wire.host_initiated)
        {
            let [request] = method.params.as_slice() else {
                bail!(
                    "Host-initiated method `{}` must have exactly one request parameter",
                    method.name
                );
            };
            let request_name = versioned_wrapper_root(
                &method.name,
                "host-initiated request",
                &request.type_ref,
                &wrappers,
            )?;
            let ReturnType::Subscription(item) = &method.return_type else {
                bail!(
                    "Host-initiated method `{}` must return Subscription<T>",
                    method.name
                );
            };
            let item_name =
                versioned_wrapper_root(&method.name, "host-initiated item", item, &wrappers)?;
            let wire_name = wire_method_name(&trait_def.name, &method.name);
            let ids = const_name(&wire_name);
            let request_path = format!("versioned::{module}::{request_name}");
            let item_path = format!("versioned::{module}::{item_name}");

            writedoc!(
                out,
                r#"

                /// Start the host-initiated `{wire_name}` subscription.
                pub(crate) fn {wire_name}(
                    subscriptions: &HostInitiatedSubscriptionManager,
                    transport: Arc<dyn Transport>,
                    request: {request_path},
                ) -> truapi::Subscription<Result<{item_path}, truapi::latest::GenericError>> {{
                    subscriptions.start(
                        wire_table::{ids},
                        parity_scale_codec::Encode::encode(&request),
                        transport,
                    )
                }}
                "#
            )
            .unwrap();
        }
    }
    Ok(())
}

struct MethodEmission {
    /// Rust method name on the host trait (used for the `host.<name>(...)` call).
    name: String,
    /// Fully-qualified wire method name (`{trait_snake}_{method}`); uppercased
    /// to the `wire_table` const this method registers against.
    wire_name: String,
    module: String,
    kind: MethodKind,
    request_payload: Option<WirePayload>,
    response_wrapper: Option<String>,
    error_payload: WirePayload,
    item_wrapper: Option<String>,
    required_execution: Option<String>,
}

#[derive(Clone)]
enum WirePayload {
    Versioned(String),
    /// Not a recognized versioned wrapper: a method's param, or error type,
    /// that doesn't follow the codec-2 authoring convention. No wire payload
    /// shape is representable for this, so every path that reaches it errors
    /// rather than falling back to a legacy encoding.
    Raw,
}

impl MethodEmission {
    fn build(
        api: &ApiDefinition,
        module: &str,
        wire_method: &str,
        method: &MethodDef,
        required_execution: Option<&str>,
    ) -> Result<Self> {
        let versioned_wrappers = versioned_wrapper_names(api);
        let request_payload = match method.params.as_slice() {
            [] => None,
            [param] => match &param.type_ref {
                TypeRef::Named { name, args }
                    if args.is_empty() && versioned_wrappers.contains(name) =>
                {
                    Some(WirePayload::Versioned(name.clone()))
                }
                _ => Some(WirePayload::Raw),
            },
            _ => bail!(
                "Method `{}`: expected at most one request parameter (got {})",
                method.name,
                method.params.len()
            ),
        };
        let error_payload = match &method.return_type {
            ReturnType::Result { err, .. } | ReturnType::ResultSubscription { err, .. } => {
                wire_payload_for_error(&method.name, err, &versioned_wrappers)?
            }
            ReturnType::Subscription(_) => WirePayload::Raw,
        };

        let (response_wrapper, item_wrapper) = match &method.return_type {
            // `Result<(), _>` returns produce an empty wire payload.
            // The trait method is called for its side effects and the
            // dispatcher encodes `()` (zero bytes) on success.
            ReturnType::Result {
                ok: TypeRef::Unit, ..
            } => (None, None),
            ReturnType::Result { ok, .. } => (
                Some(
                    versioned_wrapper_root(&method.name, "response", ok, &versioned_wrappers)?
                        .to_string(),
                ),
                None,
            ),
            ReturnType::Subscription(item) => (
                None,
                Some(
                    versioned_wrapper_root(
                        &method.name,
                        "subscription item",
                        item,
                        &versioned_wrappers,
                    )?
                    .to_string(),
                ),
            ),
            ReturnType::ResultSubscription { item, .. } => (
                None,
                Some(
                    versioned_wrapper_root(
                        &method.name,
                        "subscription item",
                        item,
                        &versioned_wrappers,
                    )?
                    .to_string(),
                ),
            ),
        };

        Ok(MethodEmission {
            name: method.name.clone(),
            wire_name: wire_method.to_string(),
            module: module.to_string(),
            kind: method.kind,
            request_payload,
            response_wrapper,
            error_payload,
            item_wrapper,
            required_execution: required_execution.map(str::to_string),
        })
    }

    fn write(&self, out: &mut String, host_expr: &str) -> Result<()> {
        match self.kind {
            MethodKind::Request => self.write_request_envelope(out, host_expr),
            MethodKind::Subscription | MethodKind::ResultSubscription => {
                self.write_subscription_envelope(out, host_expr)
            }
        }
    }

    /// Generates a request/response handler. The incoming bytes decode
    /// directly as the method's request wrapper (its own variant tag is the
    /// version); the reply is `Result<{Response}, CallError<{Error}>>`,
    /// downgraded to the version the request wrapper carried.
    fn write_request_envelope(&self, out: &mut String, host_expr: &str) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);

        let Some(WirePayload::Versioned(request_name)) = &self.request_payload else {
            bail!("Method `{method}`: every request method needs a versioned request wrapper");
        };
        let Some(error_name) = self.error_payload.versioned_name() else {
            bail!("Method `{method}`: every request method needs a versioned error wrapper");
        };
        let request_path = format!("versioned::{module}::{request_name}");
        let error_path = format!("versioned::{module}::{error_name}");
        let response_path = self
            .response_wrapper
            .as_ref()
            .map(|name| format!("versioned::{module}::{name}"));
        let response_ty = response_path.as_deref().unwrap_or("()");

        writeln!(out, "    {{").unwrap();
        self.write_execution_binding(out);
        write_indented(
            out,
            8,
            &formatdoc! {
                r#"
                let host = {host_expr};
                dispatcher.on_request(wire_table::{ids}, move |request_id: String, bytes: Vec<u8>| {{
                    let host = host.clone();
                    Box::pin(async move {{
                "#
            },
        );

        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                let request: {request_path} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(request) => request,
                    Err(err) => {{
                        let error: truapi::CallError<{error_path}> =
                            truapi::CallError::MalformedFrame {{ reason: err.to_string() }};
                        let result: Result<{response_ty}, truapi::CallError<{error_path}>> = Err(error);
                        return Ok(result.encode());
                    }}
                }};
                let target_version = request.version();
                let cx = CallContext::with_request_id(request_id.clone());
                "#
            },
        );

        if self.required_execution.is_some() {
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    if !execution_allowed {{
                        let error: truapi::CallError<{error_path}> = truapi::CallError::Denied;
                        let result: Result<{response_ty}, truapi::CallError<{error_path}>> = Err(error);
                        return Ok(result.encode());
                    }}
                    "#
                },
            );
        }

        match &response_path {
            Some(response_path) => {
                write_indented(
                    out,
                    16,
                    &formatdoc! {
                        r#"
                        let result: Result<{response_path}, truapi::CallError<{error_path}>> =
                            match host.{method}(&cx, request).await {{
                                Ok(response) => Ok(<{response_path} as truapi::versioned::FromLatest>::from_latest(
                                    truapi::versioned::IntoLatest::into_latest(response),
                                    target_version,
                                )),
                                Err(err) => Err(downgrade_call_error(err, target_version)),
                            }};
                        Ok(result.encode())
                        "#
                    },
                );
            }
            None => {
                write_indented(
                    out,
                    16,
                    &formatdoc! {
                        r#"
                        let result: Result<(), truapi::CallError<{error_path}>> = match host.{method}(&cx, request).await {{
                            Ok(()) => Ok(()),
                            Err(err) => Err(downgrade_call_error(err, target_version)),
                        }};
                        Ok(result.encode())
                        "#
                    },
                );
            }
        }

        write_indented(
            out,
            4,
            indoc! {
                r#"
                        })
                    });
                }
                "#
            },
        );
        Ok(())
    }

    /// Generates a subscription handler. The incoming bytes decode directly
    /// as the method's request wrapper (its `Start` payload), or `()` for a
    /// method with no request parameter — its version then falls back to the
    /// item wrapper's latest, since no per-request signal exists to derive one
    /// from. Items are downgraded to that version and streamed as `Receive`
    /// frames; a synchronous or mid-decode failure is streamed as one
    /// `Interrupt(Some(err))`. Natural stream completion
    /// (`Interrupt(None)`) is encoded generically by the runtime with no
    /// per-method type knowledge needed, so it isn't generated here, and
    /// `Stop` is intercepted by the framework before it ever reaches a
    /// registered handler.
    fn write_subscription_envelope(&self, out: &mut String, host_expr: &str) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);

        let Some(item_name) = self.item_wrapper.as_deref() else {
            bail!("Method `{method}`: subscription methods must have an item wrapper");
        };
        let item_path = format!("versioned::{module}::{item_name}");

        let is_result_sub = matches!(self.kind, MethodKind::ResultSubscription);
        let has_request = matches!(self.request_payload, Some(WirePayload::Versioned(_)));

        let start_ty = match &self.request_payload {
            Some(WirePayload::Versioned(request_name)) => {
                format!("versioned::{module}::{request_name}")
            }
            _ => "()".to_string(),
        };
        // A unit-typed binding trips clippy's `let_unit_value` lint, so a
        // subscription with no `Start` payload names it `_request` instead
        // of relying on a follow-up `let _ = request;` to silence it.
        let request_binding = if has_request { "request" } else { "_request" };

        let error_ty = if is_result_sub {
            let Some(error_name) = self.error_payload.versioned_name() else {
                bail!(
                    "Method `{method}`: result subscription methods must have a versioned error wrapper"
                );
            };
            format!("versioned::{module}::{error_name}")
        } else {
            "truapi::latest::GenericError".to_string()
        };

        writeln!(out, "    {{").unwrap();
        self.write_execution_binding(out);
        write_indented(
            out,
            8,
            &formatdoc! {
                r#"
                let host = {host_expr};
                dispatcher.on_subscription(wire_table::{ids}, move |request_id: String, bytes: Vec<u8>| {{
                    let host = host.clone();
                    Box::pin(async move {{
                "#
            },
        );

        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                let {request_binding}: {start_ty} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(request) => request,
                    Err(err) => {{
                        let error: truapi::CallError<{error_ty}> =
                            truapi::CallError::MalformedFrame {{ reason: err.to_string() }};
                        return Err(Some(error).encode());
                    }}
                }};
                "#
            },
        );

        if has_request {
            writeln!(
                out,
                "                let target_version = request.version();"
            )
            .unwrap();
        } else {
            write_indented(
                out,
                16,
                &format!(
                    "let target_version = <{item_path} as truapi::versioned::Versioned>::LATEST;\n"
                ),
            );
        }
        write_indented(
            out,
            16,
            "let cx = CallContext::with_request_id(request_id.clone());\n",
        );

        if self.required_execution.is_some() {
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    if !execution_allowed {{
                        let error: truapi::CallError<{error_ty}> = truapi::CallError::Denied;
                        return Err(Some(error).encode());
                    }}
                    "#
                },
            );
        }

        let call_args = if has_request { "&cx, request" } else { "&cx" };

        if is_result_sub {
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    let stream = match host.{method}({call_args}).await {{
                        Ok(sub) => sub,
                        Err(err) => {{
                            let error = downgrade_call_error(err, target_version);
                            return Err(Some(error).encode());
                        }}
                    }};
                    "#
                },
            );
        } else {
            writeln!(
                out,
                "                let stream = host.{method}({call_args}).await;"
            )
            .unwrap();
        }

        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                let stream = futures::StreamExt::map(stream, move |item: {item_path}| {{
                    <{item_path} as truapi::versioned::FromLatest>::from_latest(
                        truapi::versioned::IntoLatest::into_latest(item),
                        target_version,
                    )
                }});
                Ok(subscription_stream(stream))
                "#
            },
        );

        write_indented(
            out,
            4,
            indoc! {
                r#"
                        })
                    });
                }
                "#
            },
        );
        Ok(())
    }

    fn write_execution_binding(&self, out: &mut String) {
        if let Some(required) = self.required_execution.as_ref() {
            writeln!(
                out,
                "        let execution_allowed = dispatcher.allows_execution(ProductExecutionKind::{required});"
            )
            .unwrap();
        }
    }
}

impl WirePayload {
    fn versioned_name(&self) -> Option<&str> {
        match self {
            Self::Versioned(name) => Some(name),
            Self::Raw => None,
        }
    }
}

fn wire_payload_for_error(
    method: &str,
    ty: &TypeRef,
    versioned_wrappers: &BTreeSet<String>,
) -> Result<WirePayload> {
    let inner = call_error_inner(ty).unwrap_or(ty);
    match inner {
        TypeRef::Named { name, args } if args.is_empty() && versioned_wrappers.contains(name) => {
            Ok(WirePayload::Versioned(name.clone()))
        }
        _ => {
            if matches!(inner, TypeRef::Unit) {
                bail!("Method `{method}`: error type cannot be unit")
            }
            Ok(WirePayload::Raw)
        }
    }
}

fn versioned_wrapper_root<'a>(
    method: &str,
    role: &str,
    ty: &'a TypeRef,
    versioned_wrappers: &BTreeSet<String>,
) -> Result<&'a str> {
    let TypeRef::Named { name, args } = ty else {
        bail!("Method `{method}`: {role} is not a versioned wrapper")
    };
    if !args.is_empty() || !versioned_wrappers.contains(name) {
        bail!("Method `{method}`: {role} is not a versioned wrapper")
    }
    Ok(name)
}

fn versioned_wrapper_names(api: &ApiDefinition) -> BTreeSet<String> {
    api.types
        .iter()
        .filter_map(|ty| {
            let TypeDefKind::Enum(variants) = &ty.kind else {
                return None;
            };
            if variants.iter().all(|variant| {
                variant
                    .name
                    .strip_prefix('V')
                    .is_some_and(|version| version.parse::<u32>().is_ok())
            }) {
                Some(ty.name.clone())
            } else {
                None
            }
        })
        .collect()
}

fn call_error_inner(ty: &TypeRef) -> Option<&TypeRef> {
    match ty {
        TypeRef::Named { name, args } if name == "CallError" && args.len() == 1 => Some(&args[0]),
        _ => None,
    }
}

/// Append `block` to `out`, prefixing every non-empty line with `indent` spaces.
fn write_indented(out: &mut String, indent: usize, block: &str) {
    let pad = " ".repeat(indent);
    for line in block.lines() {
        if line.is_empty() {
            out.push('\n');
        } else {
            writeln!(out, "{pad}{line}").unwrap();
        }
    }
}

fn write_header(out: &mut String) {
    writedoc!(
        out,
        r#"
        //! Wire dispatcher for the unified `TrUApi` trait.
        //!
        //! Auto-generated by truapi-codegen. Do not edit.

        // Responses are downgraded to the caller's version uniformly, including
        // the methods whose payload is unit and for which the conversion is a
        // no-op.
        #![allow(clippy::unit_arg)]

        "#
    )
    .unwrap();
}

fn write_imports(out: &mut String, traits: &[&TraitDef]) {
    writedoc!(
        out,
        r#"
        use std::sync::Arc;

        use parity_scale_codec::{{Decode, Encode}};

        use truapi::CallContext;
        use truapi::api::{{
        "#
    )
    .unwrap();
    for trait_def in traits {
        writeln!(out, "    {},", trait_def.name).unwrap();
    }
    writedoc!(
        out,
        r#"
        }};
        use truapi::versioned::{{self, Versioned}};
        use truapi_platform::ProductExecutionKind;

        use crate::dispatcher::Dispatcher;
        use crate::frame::downgrade_call_error;
        use crate::generated::wire_table;
        use crate::subscription::{{HostInitiatedSubscriptionManager, subscription_stream}};
        use crate::transport::Transport;
        "#
    )
    .unwrap();
}

fn write_top_register(out: &mut String, traits: &[&TraitDef]) {
    writedoc!(
        out,
        r#"
        /// Register every TrUAPI method with the dispatcher.
        pub fn register<P>(dispatcher: &mut Dispatcher, host: Arc<P>)
        where
            P: truapi::api::TrUApi + 'static,
        {{
        "#
    )
    .unwrap();
    let last = traits.len().saturating_sub(1);
    for (idx, trait_def) in traits.iter().enumerate() {
        let host_expr = if idx == last { "host" } else { "host.clone()" };
        let module = module_for_trait(&trait_def.name);
        writeln!(out, "    register_{module}(dispatcher, {host_expr});").unwrap();
    }
    writeln!(out, "}}").unwrap();
}
