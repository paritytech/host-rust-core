//! Emits `dispatcher.rs`: the server-side wire dispatcher that routes
//! incoming frames to the host trait implementation.
//!
//! For each method the emitter produces an `on_request` (or
//! `on_subscription`) registration that:
//! 1. SCALE-decodes the versioned request wrapper from the wire bytes.
//! 2. Calls the host trait method (which receives the wrapper directly
//!    and matches `_::V1(inner)` internally).
//! 3. SCALE-encodes the versioned response wrapper back onto the wire.
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
        method.write(&mut code, api, host_expr)?;
    }
    writeln!(code, "}}").unwrap();

    Ok(code)
}

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
            let request = versioned_wrapper_root(
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
            let item =
                versioned_wrapper_root(&method.name, "host-initiated item", item, &wrappers)?;
            let wire_name = wire_method_name(&trait_def.name, &method.name);
            let ids = const_name(&wire_name);
            let request_path = format!("versioned::{module}::{request}");

            let version_type = envelope_type_name(Some(request), Some(item)).ok_or_else(|| {
                anyhow::anyhow!(
                    "Host-initiated method `{}`: request/item wrapper name does not follow the \
                     {{Base}}Request/{{Base}}Item convention, so no wire envelope can be derived \
                     for it",
                    method.name
                )
            })?;
            let version_variant = single_variant(api, &version_type)?;
            let request_variant = single_variant(api, request)?;
            let envelope_path = format!("versioned::{module}::{version_type}");
            let bind = envelope_bind_name(request_variant);
            let version_number: u8 = version_variant
                .name
                .strip_prefix('V')
                .and_then(|n| n.parse().ok())
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "Host-initiated method `{}`: envelope variant `{}` is not named `V<number>`",
                        method.name,
                        version_variant.name
                    )
                })?;
            let start_body = formatdoc! {r#"
                let envelope = match request {{
                    {request_pat} => {envelope_path}::{ev_name}(truapi::versioned::Subscription::Start({bind})),
                }};
                subscriptions.start(
                    wire_table::{ids},
                    {version_number},
                    parity_scale_codec::Encode::encode(&envelope),
                    transport,
                )
                "#,
                request_pat = variant_expr(&request_path, request_variant, bind),
                ev_name = version_variant.name,
            };

            writedoc!(
                out,
                r#"

                /// Start the host-initiated `{wire_name}` subscription.
                pub(crate) fn {wire_name}(
                    subscriptions: &HostInitiatedSubscriptionManager,
                    transport: Arc<dyn Transport>,
                    request: {request_path},
                ) -> truapi::Subscription<
                    Result<versioned::{module}::{item}, truapi::latest::GenericError>,
                > {{
                "#
            )
            .unwrap();
            write_indented(out, 4, &start_body);
            writeln!(out, "}}").unwrap();
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
    /// that doesn't follow the codec-2 authoring convention. The nested
    /// envelope has no representable shape for this, so every path that
    /// reaches it errors rather than falling back to a legacy encoding.
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

    fn write(&self, out: &mut String, api: &ApiDefinition, host_expr: &str) -> Result<()> {
        match self.kind {
            MethodKind::Request => self.write_request(out, api, host_expr),
            MethodKind::Subscription | MethodKind::ResultSubscription => {
                self.write_subscription(out, api, host_expr)
            }
        }
    }

    /// The merged `{Method}Version` wire-envelope type this method uses.
    /// Derived from the request or item wrapper's name (stripping its
    /// `Request`/`Item` suffix, per the authoring convention every real
    /// method follows). Either failure mode here — a wrapper name outside
    /// that convention, or a derived name that doesn't resolve to a real
    /// single-version wrapper — means the method has no valid codec-2
    /// payload shape, so this errors instead of silently falling back to a
    /// directionless payload.
    fn envelope<'a>(&self, api: &'a ApiDefinition) -> Result<EnvelopeInfo<'a>> {
        let request_name = match &self.request_payload {
            Some(WirePayload::Versioned(name)) => Some(name.as_str()),
            _ => None,
        };
        let method = &self.name;
        let type_name =
            envelope_type_name(request_name, self.item_wrapper.as_deref()).ok_or_else(|| {
                anyhow::anyhow!(
                    "Method `{method}`: request/item wrapper name does not follow the \
                     {{Base}}Request/{{Base}}Item convention, so no wire envelope can be \
                     derived for it"
                )
            })?;
        let variant = single_variant(api, &type_name)?;
        Ok(EnvelopeInfo { type_name, variant })
    }

    fn write_request(&self, out: &mut String, api: &ApiDefinition, host_expr: &str) -> Result<()> {
        let env = self.envelope(api)?;
        self.write_request_envelope(out, api, host_expr, &env)
    }

    fn write_subscription(
        &self,
        out: &mut String,
        api: &ApiDefinition,
        host_expr: &str,
    ) -> Result<()> {
        let env = self.envelope(api)?;
        self.write_subscription_envelope(out, api, host_expr, &env)
    }

    fn write_request_envelope(
        &self,
        out: &mut String,
        api: &ApiDefinition,
        host_expr: &str,
        env: &EnvelopeInfo<'_>,
    ) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);
        let envelope_path = format!("versioned::{module}::{}", env.type_name);
        let version_variant = &env.variant.name;

        let Some(WirePayload::Versioned(request_name)) = &self.request_payload else {
            bail!("Method `{method}`: nested envelope requires a versioned request");
        };
        let Some(error_name) = self.error_payload.versioned_name() else {
            bail!("Method `{method}`: nested envelope requires a versioned error");
        };
        let request_variant = single_variant(api, request_name)?;
        let error_variant = single_variant(api, error_name)?;
        let error_bare_ty = variant_bare_type(error_variant)?;
        let request_path = format!("versioned::{module}::{request_name}");
        let error_path = format!("versioned::{module}::{error_name}");

        let wrap_response = |inner: &str| {
            format!(
                "{envelope_path}::{version_variant}(truapi::versioned::Request::Response({inner}))"
            )
        };

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
                let envelope: {envelope_path} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(envelope) => envelope,
                    Err(err) => {{
                        let error: truapi::CallError<{error_bare_ty}> =
                            truapi::CallError::MalformedFrame {{ reason: err.to_string() }};
                        return Ok({wrap_err}.encode());
                    }}
                }};
                let request: {request_path} = match envelope {{
                    {envelope_path}::{version_variant}(truapi::versioned::Request::Request({bind})) => {request_ctor},
                    _ => {{
                        let error: truapi::CallError<{error_bare_ty}> =
                            truapi::CallError::MalformedFrame {{
                                reason: "expected a request-direction frame".to_string(),
                            }};
                        return Ok({wrap_err}.encode());
                    }}
                }};
                let target_version = request.version();
                let cx = CallContext::with_request_id(request_id.clone());
                "#,
                bind = envelope_bind_name(request_variant),
                request_ctor = variant_expr(&request_path, request_variant, envelope_bind_name(request_variant)),
                wrap_err = wrap_response("Err(error)"),
            },
        );

        if self.required_execution.is_some() {
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    if !execution_allowed {{
                        let error: truapi::CallError<{error_bare_ty}> = truapi::CallError::Denied;
                        return Ok({wrap_err}.encode());
                    }}
                    "#,
                    wrap_err = wrap_response("Err(error)"),
                },
            );
        }

        let unwrap_call_error = rewrap_call_error(&error_path, error_variant, "downgraded");

        match &self.response_wrapper {
            Some(response_name) => {
                let response_variant = single_variant(api, response_name)?;
                let response_path = format!("versioned::{module}::{response_name}");
                let ok_extract = bare_ident_or_unit(response_variant);
                write_indented(
                    out,
                    16,
                    &formatdoc! {
                        r#"
                        let response: {response_path} = match host.{method}(&cx, request).await {{
                            Ok(value) => value,
                            Err(err) => {{
                                let downgraded = downgrade_call_error(err, target_version);
                                let error: truapi::CallError<{error_bare_ty}> = {unwrap_call_error};
                                return Ok({wrap_err}.encode());
                            }}
                        }};
                        let response = <{response_path} as truapi::versioned::FromLatest>::from_latest(
                            truapi::versioned::IntoLatest::into_latest(response),
                            target_version,
                        );
                        // Downgraded to the caller's version: a handler answers in
                        // latest terms, and a peer that asked in an older version
                        // cannot decode a newer variant.
                        Ok(match response {{
                            {response_pat} => {wrap_ok},
                        }}.encode())
                        "#,
                        wrap_err = wrap_response("Err(error)"),
                        response_pat = variant_expr(&response_path, response_variant, "bare"),
                        wrap_ok = wrap_response(&format!("Ok({ok_extract})")),
                    },
                );
            }
            None => {
                write_indented(
                    out,
                    16,
                    &formatdoc! {
                        r#"
                        match host.{method}(&cx, request).await {{
                            Ok(()) => Ok({wrap_unit_ok}.encode()),
                            Err(err) => {{
                                let downgraded = downgrade_call_error(err, target_version);
                                let error: truapi::CallError<{error_bare_ty}> = {unwrap_call_error};
                                Ok({wrap_err}.encode())
                            }}
                        }}
                        "#,
                        wrap_unit_ok = wrap_response("Ok(())"),
                        wrap_err = wrap_response("Err(error)"),
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

    /// Generates a subscription handler through the nested wire envelope:
    /// incoming bytes are the merged `{Method}Version` type, matched for the
    /// `Start` direction (the framework intercepts `Stop` frames before they
    /// ever reach a registered handler, so only `Start` is handled here);
    /// outgoing item frames are constructed as that type's `Receive`
    /// direction. Natural stream completion (`Interrupt(None)`) is encoded
    /// generically by the runtime with no per-method type knowledge needed,
    /// so it isn't generated here.
    fn write_subscription_envelope(
        &self,
        out: &mut String,
        api: &ApiDefinition,
        host_expr: &str,
        env: &EnvelopeInfo<'_>,
    ) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);
        let envelope_path = format!("versioned::{module}::{}", env.type_name);
        let version_variant = &env.variant.name;
        // The nested envelope currently supports exactly one version per
        // method (see `single_variant`), so the version number is this
        // literal, not something decoded per frame.
        let version_number: u8 = version_variant
            .strip_prefix('V')
            .and_then(|n| n.parse().ok())
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "Method `{method}`: envelope variant `{version_variant}` is not named `V<number>`"
                )
            })?;

        let Some(item_name) = self.item_wrapper.as_deref() else {
            bail!("Method `{method}`: subscription methods must have an item wrapper");
        };
        let item_variant = single_variant(api, item_name)?;
        let item_path = format!("versioned::{module}::{item_name}");

        let is_result_sub = matches!(self.kind, MethodKind::ResultSubscription);
        let has_request = matches!(self.request_payload, Some(WirePayload::Versioned(_)));

        let (start_ty, start_ctor, start_bind) = match &self.request_payload {
            Some(WirePayload::Versioned(request_name)) => {
                let request_variant = single_variant(api, request_name)?;
                let request_path = format!("versioned::{module}::{request_name}");
                let bind = envelope_bind_name(request_variant);
                (
                    request_path.clone(),
                    variant_expr(&request_path, request_variant, bind),
                    bind,
                )
            }
            _ => ("()".to_string(), "()".to_string(), "_bare"),
        };

        let error_bare_ty = if is_result_sub {
            let Some(error_name) = self.error_payload.versioned_name() else {
                bail!(
                    "Method `{method}`: result subscription methods must have a versioned error wrapper"
                );
            };
            variant_bare_type(single_variant(api, error_name)?)?
        } else {
            "truapi::latest::GenericError".to_string()
        };

        let wrap_start_err = format!(
            "{envelope_path}::{version_variant}(truapi::versioned::Subscription::Interrupt(Some(error)))"
        );
        // A unit-typed binding trips clippy's `let_unit_value` lint, so a
        // subscription with no `Start` payload names it `_request` instead
        // of relying on a follow-up `let _ = request;` to silence it.
        let request_binding = if has_request { "request" } else { "_request" };

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
                let envelope: {envelope_path} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(envelope) => envelope,
                    Err(err) => {{
                        let error: truapi::CallError<{error_bare_ty}> =
                            truapi::CallError::MalformedFrame {{ reason: err.to_string() }};
                        return Err({wrap_start_err}.encode());
                    }}
                }};
                let {request_binding}: {start_ty} = match envelope {{
                    {envelope_path}::{version_variant}(truapi::versioned::Subscription::Start({start_bind})) => {start_ctor},
                    _ => {{
                        let error: truapi::CallError<{error_bare_ty}> =
                            truapi::CallError::MalformedFrame {{
                                reason: "expected a start-direction frame".to_string(),
                            }};
                        return Err({wrap_start_err}.encode());
                    }}
                }};
                let cx = CallContext::with_request_id(request_id.clone());
                "#
            },
        );
        let call_args = if has_request { "&cx, request" } else { "&cx" };

        if self.required_execution.is_some() {
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    if !execution_allowed {{
                        let error: truapi::CallError<{error_bare_ty}> = truapi::CallError::Denied;
                        return Err({wrap_start_err}.encode());
                    }}
                    "#
                },
            );
        }

        if is_result_sub {
            let error_name = self.error_payload.versioned_name().expect("checked above");
            let error_variant = single_variant(api, error_name)?;
            let error_path = format!("versioned::{module}::{error_name}");
            let unwrap_call_error = rewrap_call_error(&error_path, error_variant, "downgraded");
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    let stream = match host.{method}({call_args}).await {{
                        Ok(sub) => sub,
                        Err(err) => {{
                            let downgraded = downgrade_call_error(err, {version_number});
                            let error: truapi::CallError<{error_bare_ty}> = {unwrap_call_error};
                            return Err({wrap_start_err}.encode());
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
                let stream = futures::StreamExt::map(stream, |item: {item_path}| match item {{
                    {item_pat} => {envelope_path}::{version_variant}(
                        truapi::versioned::Subscription::Receive({item_extract}),
                    ),
                }});
                Ok(({version_number}, subscription_stream::<{envelope_path}, _>(stream)))
                "#,
                item_pat = variant_expr(&item_path, item_variant, "bare"),
                item_extract = bare_ident_or_unit(item_variant),
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

/// The merged wire-envelope type this method's frames nest into
/// (`{Method}Version`), and its single declared version variant. Only
/// single-version envelopes are currently generated; see [`single_variant`].
struct EnvelopeInfo<'a> {
    type_name: String,
    variant: &'a VariantDef,
}

/// Derive the merged `{Method}Version` wire-envelope type name from a
/// method's request or item wrapper name, stripping its `Request`/`Item`
/// suffix — the naming convention every hand-authored envelope type follows.
/// Returns `None` when neither name is present or neither ends in the
/// expected suffix; every real method's wrapper follows the convention, so
/// callers turn `None` into a hard codegen error instead of falling back.
fn envelope_type_name(request: Option<&str>, item: Option<&str>) -> Option<String> {
    if let Some(base) = request.and_then(|name| name.strip_suffix("Request")) {
        return Some(format!("{base}Version"));
    }
    if let Some(base) = item.and_then(|name| name.strip_suffix("Item")) {
        return Some(format!("{base}Version"));
    }
    None
}

/// Look up a versioned wrapper type's single declared variant. The nested
/// wire envelope currently supports exactly one version per method; a type
/// with more is a hard error rather than a silent partial implementation.
fn single_variant<'a>(api: &'a ApiDefinition, name: &str) -> Result<&'a VariantDef> {
    let type_def = api
        .types
        .iter()
        .find(|type_def| type_def.name == name)
        .ok_or_else(|| {
            anyhow::anyhow!("versioned wrapper type `{name}` not found in extracted API")
        })?;
    let TypeDefKind::Enum(variants) = &type_def.kind else {
        bail!("versioned wrapper type `{name}` is not an enum");
    };
    match variants.as_slice() {
        [only] => Ok(only),
        other => bail!(
            "versioned wrapper `{name}` has {} versions; the nested wire envelope \
             currently supports exactly one version per method",
            other.len()
        ),
    }
}

/// Rust expression naming `variant` of `type_path`: either constructing it
/// from `bare_ident`, or (identical syntax) pattern-matching it and binding
/// `bare_ident` — unit variants take neither parens nor `bare_ident`.
fn variant_expr(type_path: &str, variant: &VariantDef, bare_ident: &str) -> String {
    match &variant.fields {
        VariantFields::Unit => format!("{type_path}::{}", variant.name),
        VariantFields::Unnamed(_) => format!("{type_path}::{}({bare_ident})", variant.name),
        VariantFields::Named(_) => {
            unreachable!("versioned wrapper variants are unit or single-field tuples")
        }
    }
}

/// The identifier (or unit literal) a matched [`variant_expr`] binds:
/// `"bare"` for a single-field tuple variant, `"()"` for a unit variant.
fn bare_ident_or_unit(variant: &VariantDef) -> &'static str {
    match &variant.fields {
        VariantFields::Unit => "()",
        VariantFields::Unnamed(_) => "bare",
        VariantFields::Named(_) => {
            unreachable!("versioned wrapper variants are unit or single-field tuples")
        }
    }
}

/// Identifier to bind an envelope direction tag's inner value as (`Request`,
/// `Start`, ...), which is always structurally present even when the
/// destination variant it reconstructs is a unit that discards it. Binding
/// as `"bare"` when the destination will reference it and `"_bare"` when it
/// won't avoids an unused-variable warning on the otherwise-always-present
/// envelope binding.
fn envelope_bind_name(destination_variant: &VariantDef) -> &'static str {
    match &destination_variant.fields {
        VariantFields::Unit => "_bare",
        VariantFields::Unnamed(_) => "bare",
        VariantFields::Named(_) => {
            unreachable!("versioned wrapper variants are unit or single-field tuples")
        }
    }
}

/// The Rust type of `variant`'s bare payload (`()` for a unit variant).
fn variant_bare_type(variant: &VariantDef) -> Result<String> {
    match &variant.fields {
        VariantFields::Unit => Ok("()".to_string()),
        VariantFields::Unnamed(types) if types.len() == 1 => rust_type_ref(&types[0]),
        _ => bail!(
            "versioned wrapper variant `{}` must be unit or a single-field tuple",
            variant.name
        ),
    }
}

/// Emit a match expression that rewraps a `truapi::CallError<{old versioned
/// error}>` value (`scrutinee`) into `truapi::CallError<{bare domain
/// error}>` — unwrapping the domain payload's own (now-redundant) version
/// tag, since the nested envelope's outer version tag already carries that
/// information. Framework variants (`Denied`/`Unsupported`/`MalformedFrame`/
/// `HostFailure`) carry no domain payload and pass through unchanged.
fn rewrap_call_error(error_path: &str, error_variant: &VariantDef, scrutinee: &str) -> String {
    let domain_pattern = variant_expr(error_path, error_variant, "bare");
    let domain_bare = bare_ident_or_unit(error_variant);
    formatdoc! {r#"
        match {scrutinee} {{
            truapi::CallError::Domain({domain_pattern}) => truapi::CallError::Domain({domain_bare}),
            truapi::CallError::Denied => truapi::CallError::Denied,
            truapi::CallError::Unsupported => truapi::CallError::Unsupported,
            truapi::CallError::MalformedFrame {{ reason }} => truapi::CallError::MalformedFrame {{ reason }},
            truapi::CallError::HostFailure {{ reason }} => truapi::CallError::HostFailure {{ reason }},
        }}"#
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

fn rust_type_ref(ty: &TypeRef) -> Result<String> {
    match ty {
        TypeRef::Primitive(name) => Ok(match name.as_str() {
            "str" => "String".to_string(),
            "compact" => "u128".to_string(),
            "optionBool" => "parity_scale_codec::OptionBool".to_string(),
            other => other.to_string(),
        }),
        TypeRef::Named { name, args } if name == "CallError" && args.len() == 1 => {
            Ok(format!("truapi::CallError<{}>", rust_type_ref(&args[0])?))
        }
        TypeRef::Named { name, args } if args.is_empty() => {
            if let Some((version, base)) = version_prefixed_type(name) {
                Ok(format!("truapi::v{version:02}::{base}"))
            } else {
                Ok(format!("truapi::v01::{name}"))
            }
        }
        TypeRef::Named { name, args } => {
            let args = args
                .iter()
                .map(rust_type_ref)
                .collect::<Result<Vec<_>>>()?
                .join(", ");
            Ok(format!("truapi::v01::{name}<{args}>"))
        }
        TypeRef::Vec(inner) => Ok(format!("Vec<{}>", rust_type_ref(inner)?)),
        TypeRef::Option(inner) => Ok(format!("Option<{}>", rust_type_ref(inner)?)),
        TypeRef::Tuple(items) => {
            let items = items
                .iter()
                .map(rust_type_ref)
                .collect::<Result<Vec<_>>>()?
                .join(", ");
            Ok(format!("({items})"))
        }
        TypeRef::Array(inner, len) => Ok(format!("[{}; {len}]", rust_type_ref(inner)?)),
        TypeRef::Generic(name) => Ok(name.clone()),
        TypeRef::Unit => Ok("()".to_string()),
    }
}

fn version_prefixed_type(name: &str) -> Option<(u32, &str)> {
    let rest = name.strip_prefix('V')?;
    if rest.len() < 3 {
        return None;
    }
    let (version, base) = rest.split_at(2);
    if base.is_empty() {
        return None;
    }
    Some((version.parse().ok()?, base))
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
