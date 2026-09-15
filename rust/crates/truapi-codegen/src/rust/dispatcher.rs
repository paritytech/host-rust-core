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
        method.write(&mut code, host_expr)?;
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
            writedoc!(
                out,
                r#"

                /// Start the host-initiated `{wire_name}` subscription.
                pub(crate) fn {wire_name}(
                    subscriptions: &HostInitiatedSubscriptionManager,
                    transport: Arc<dyn Transport>,
                    request: versioned::{module}::{request},
                ) -> truapi::Subscription<
                    Result<versioned::{module}::{item}, truapi::latest::GenericError>,
                > {{
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
    request_payload: String,
    response_wrapper: Option<String>,
    /// Versioned error wrapper, absent only for a subscription that cannot fail.
    error_payload: Option<String>,
    item_wrapper: Option<String>,
    required_execution: Option<String>,
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
            [param] => versioned_wrapper_root(
                &method.name,
                "request",
                &param.type_ref,
                &versioned_wrappers,
            )?
            .to_string(),
            params => bail!(
                "Method `{}`: expected exactly one request parameter (got {})",
                method.name,
                params.len()
            ),
        };
        let error_payload = match &method.return_type {
            ReturnType::Result { err, .. } | ReturnType::ResultSubscription { err, .. } => Some(
                versioned_error_wrapper(&method.name, err, &versioned_wrappers)?,
            ),
            ReturnType::Subscription(_) => None,
        };

        let (response_wrapper, item_wrapper) = match &method.return_type {
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
            MethodKind::Request => self.write_request(out, host_expr),
            MethodKind::Subscription | MethodKind::ResultSubscription => {
                self.write_subscription(out, host_expr)
            }
        }
    }

    fn write_request(&self, out: &mut String, host_expr: &str) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);

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
        let request = &self.request_payload;
        let Some(error) = self.error_payload.as_deref() else {
            bail!("Method `{method}`: versioned request methods must use versioned errors");
        };
        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                let request: versioned::{module}::{request} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(request) => request,
                    Err(err) => {{
                        let error: truapi::CallError<versioned::{module}::{error}> =
                            truapi::CallError::MalformedFrame {{ reason: err.to_string() }};
                        return Ok(encode_versioned_err_payload(
                            error,
                            <versioned::{module}::{error} as Versioned>::LATEST,
                        ));
                    }}
                }};
                let target_version = request.version();
                "#
            },
        );
        let call_args = "&cx, request";
        let target_version_expr = "target_version";
        writeln!(
            out,
            "                let cx = CallContext::with_request_id(request_id.clone());"
        )
        .unwrap();
        self.write_request_execution_check(out, target_version_expr)?;
        match &self.response_wrapper {
            Some(response) => {
                write_indented(
                    out,
                    16,
                    &formatdoc! {
                        r#"
                        let response: versioned::{module}::{response} = match host.{method}({call_args}).await {{
                            Ok(value) => value,
                            Err(err) => {{
                                return Ok(encode_versioned_err_payload(
                                    downgrade_call_error(err, {target_version_expr}),
                                    {target_version_expr},
                                ));
                            }}
                        }};
                        // Downgraded to the caller's version: a handler answers in
                        // latest terms, and a peer that asked in an older version
                        // cannot decode a newer variant.
                        Ok(encode_versioned_ok_payload(
                            <versioned::{module}::{response} as truapi::versioned::FromLatest>::from_latest(
                                truapi::versioned::IntoLatest::into_latest(response),
                                {target_version_expr},
                            ),
                        ))
                        "#
                    },
                );
            }
            None => bail!("Method `{method}`: response is not a versioned wrapper"),
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

    fn write_subscription(&self, out: &mut String, host_expr: &str) -> Result<()> {
        let module = &self.module;
        let method = &self.name;
        let ids = const_name(&self.wire_name);
        let Some(item) = self.item_wrapper.as_deref() else {
            bail!("Method `{method}`: subscription methods must have an item wrapper");
        };
        let error = self.error_payload.as_deref();

        let is_result_sub = matches!(self.kind, MethodKind::ResultSubscription);

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
        let request = &self.request_payload;
        let decode_error = match error {
            Some(error) => {
                let block = formatdoc! {
                    r#"
                    Err(err) => {{
                        let error: truapi::CallError<versioned::{module}::{error}> =
                            truapi::CallError::MalformedFrame {{
                                reason: err.to_string(),
                            }};
                        return Err(encode_versioned_interrupt_payload(
                            error,
                            <versioned::{module}::{error} as Versioned>::LATEST,
                        ));
                    }}
                    "#
                };
                block
                    .lines()
                    .map(|line| format!("    {line}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            }
            None => "    Err(_) => return Err(Vec::new()),".to_string(),
        };
        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                let request: versioned::{module}::{request} = match Decode::decode(&mut &bytes[..]) {{
                    Ok(request) => request,
                {decode_error}
                }};
                "#
            },
        );
        if is_result_sub {
            writeln!(
                out,
                "                let target_version = request.version();"
            )
            .unwrap();
        }
        let call_args = "&cx, request";
        let target_version_expr = "target_version";
        writeln!(
            out,
            "                let cx = CallContext::with_request_id(request_id.clone());"
        )
        .unwrap();
        if self.required_execution.is_some() && is_result_sub {
            let error = error.expect("result subscription error checked above");
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    if !execution_allowed {{
                        let error: truapi::CallError<versioned::{module}::{error}> =
                            truapi::CallError::Denied;
                        return Err(encode_versioned_interrupt_payload(error, {target_version_expr}));
                    }}
                    "#
                },
            );
        } else if self.required_execution.is_some() {
            writeln!(
                out,
                "                if !execution_allowed {{ return Err(Vec::new()); }}"
            )
            .unwrap();
        }
        if is_result_sub {
            if error.is_none() {
                bail!("Method `{method}`: result subscription methods must have an error wrapper");
            }
            write_indented(
                out,
                16,
                &formatdoc! {
                    r#"
                    let stream = match host.{method}({call_args}).await {{
                        Ok(sub) => sub,
                        Err(err) => {{
                            return Err(encode_versioned_interrupt_payload(err, {target_version_expr}));
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
        writeln!(
            out,
            "                Ok(subscription_stream::<versioned::{module}::{item}, _>(stream))"
        )
        .unwrap();
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

    fn write_request_execution_check(&self, out: &mut String, target: &str) -> Result<()> {
        if self.required_execution.is_none() {
            return Ok(());
        }
        let module = &self.module;
        let Some(error) = self.error_payload.as_deref() else {
            bail!(
                "Method `{}`: execution-filtered request has no versioned error",
                self.name
            );
        };
        write_indented(
            out,
            16,
            &formatdoc! {
                r#"
                if !execution_allowed {{
                    let error: truapi::CallError<versioned::{module}::{error}> =
                        truapi::CallError::Denied;
                    return Ok(encode_versioned_err_payload(error, {target}));
                }}
                "#
            },
        );
        Ok(())
    }
}

/// Resolve a method's error payload to its versioned wrapper. Every declared
/// error is a wrapper; anything else is a contract the wire cannot describe.
fn versioned_error_wrapper(
    method: &str,
    ty: &TypeRef,
    versioned_wrappers: &BTreeSet<String>,
) -> Result<String> {
    let inner = call_error_inner(ty).unwrap_or(ty);
    versioned_wrapper_root(method, "error", inner, versioned_wrappers).map(ToString::to_string)
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

        use parity_scale_codec::Decode;

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
        use crate::frame::encode_versioned_err_payload;
        use crate::frame::encode_versioned_interrupt_payload;
        use crate::frame::downgrade_call_error;
        use crate::frame::encode_versioned_ok_payload;
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
