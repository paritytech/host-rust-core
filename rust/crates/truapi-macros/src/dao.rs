//! Data-access objects: SQL-annotated trait methods turned into `rusqlite`
//! calls, plus an async twin that takes its connection from the core `Db`.

use std::collections::BTreeSet;

use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::{format_ident, quote};
use syn::ext::IdentExt;
use syn::spanned::Spanned;
use syn::{
    Attribute, Error, FnArg, GenericArgument, GenericParam, Ident, ItemTrait, LitStr, Pat,
    PathArguments, ReturnType, TraitItem, TraitItemFn, Type, Visibility, parse_macro_input,
};

/// Method names a DAO method cannot take: `new` is the generated `…Db`
/// constructor, and the rest are `rusqlite` 0.40 `Connection` and
/// `Transaction` methods, which `self.name(…)` in a `#[transaction]` body would
/// call instead of the DAO method.
const RESERVED_METHODS: &[&str] = &[
    "new",
    "apply",
    "apply_strm",
    "authorizer",
    "backup",
    "blob_open",
    "busy_handler",
    "busy_timeout",
    "cache_flush",
    "changes",
    "close",
    "collation_needed",
    "column_exists",
    "column_metadata",
    "commit",
    "commit_hook",
    "create_aggregate_function",
    "create_collation",
    "create_module",
    "create_scalar_function",
    "create_window_function",
    "db_config",
    "db_name",
    "deserialize",
    "deserialize_bytes",
    "deserialize_read_exact",
    "drop_behavior",
    "execute",
    "execute_batch",
    "extension_init2",
    "finish",
    "flush_prepared_statement_cache",
    "from_handle",
    "from_handle_owned",
    "get_interrupt_handle",
    "handle",
    "is_autocommit",
    "is_busy",
    "is_interrupted",
    "is_readonly",
    "last_insert_rowid",
    "limit",
    "load_extension",
    "load_extension_disable",
    "load_extension_enable",
    "new_unchecked",
    "one_column",
    "open",
    "open_in_memory",
    "open_in_memory_with_flags",
    "open_in_memory_with_flags_and_vfs",
    "open_with_flags",
    "open_with_flags_and_vfs",
    "path",
    "pragma",
    "pragma_query",
    "pragma_query_value",
    "pragma_update",
    "pragma_update_and_check",
    "prepare",
    "prepare_cached",
    "prepare_with_flags",
    "preupdate_hook",
    "profile",
    "progress_handler",
    "query_one",
    "query_row",
    "query_row_and_then",
    "release_memory",
    "remove_collation",
    "remove_function",
    "restore",
    "rollback",
    "rollback_hook",
    "savepoint",
    "savepoint_with_name",
    "serialize",
    "set_db_config",
    "set_drop_behavior",
    "set_errmsg",
    "set_limit",
    "set_prepared_statement_cache_capacity",
    "set_transaction_behavior",
    "table_exists",
    "total_changes",
    "trace",
    "trace_v2",
    "transaction",
    "transaction_state",
    "transaction_with_behavior",
    "unchecked_transaction",
    "update_hook",
    "wal_hook",
];

/// What a method does, from its marker attribute.
enum Kind {
    /// `#[query("…")]`: reads rows on a read-only connection.
    Query { sql: LitStr, rows: Rows },
    /// `#[execute("…")]`: changes rows on the writer.
    Execute { sql: LitStr, outcome: Outcome },
    /// `#[transaction]`: a body over the other methods, run as one write.
    Transaction,
}

/// Which rows a statement returns, from its declared return type.
enum Rows {
    /// `Vec<T>`: every row.
    Many(Box<Type>),
    /// `Option<T>`: the first row, if any.
    Optional(Box<Type>),
    /// `T`: the first row, which must exist.
    One(Box<Type>),
}

/// What an execute returns, from its declared return type.
enum Outcome {
    /// `usize`: rows changed.
    Changed,
    /// `()`: nothing.
    Nothing,
    /// Rows from a `RETURNING` clause.
    Returned(Rows),
}

/// How an argument crosses into the `'static` closure of the async twin.
enum Ownership {
    /// Owned already; moved in.
    Owned,
    /// `&T`: copied with `ToOwned`, lent back with `Borrow`.
    Reference,
    /// `Option<&T>`: the same, inside the option.
    OptionalReference,
}

struct Argument {
    name: Ident,
    ty: Type,
    ownership: Ownership,
}

impl Argument {
    /// The name SQL uses, without a raw-identifier prefix.
    fn sql_name(&self) -> String {
        self.name.unraw().to_string()
    }
}

struct Method {
    function: TraitItemFn,
    kind: Kind,
    arguments: Vec<Argument>,
    value: Type,
    /// `#[cfg]` attributes, repeated on everything generated for the method.
    cfgs: Vec<Attribute>,
    /// Attributes that also apply to the async twin: `cfg_attr`, lint levels
    /// and `deprecated`. Lint levels also apply to a transaction body.
    twin_attributes: Vec<Attribute>,
    /// Lint-level attributes, for the transaction body's implementation.
    lints: Vec<Attribute>,
    /// Whether the method is `#[deprecated]`, so the twin's call is allowed.
    deprecated: bool,
}

/// Parse the macro input and emit generated code or a compiler diagnostic.
pub(super) fn expand(args: TokenStream, item: TokenStream) -> TokenStream {
    if !args.is_empty() {
        let args = TokenStream2::from(args);
        return Error::new(args.span(), "#[dao] takes no arguments")
            .to_compile_error()
            .into();
    }
    let item = parse_macro_input!(item as ItemTrait);
    expand_trait(item)
        .unwrap_or_else(Error::into_compile_error)
        .into()
}

fn expand_trait(mut item: ItemTrait) -> syn::Result<TokenStream2> {
    let mut methods = Vec::new();
    for trait_item in &item.items {
        let TraitItem::Fn(function) = trait_item else {
            return Err(Error::new(
                trait_item.span(),
                "a #[dao] trait holds only methods",
            ));
        };
        methods.push(Method::parse(function.clone())?);
    }

    let trait_ident = &item.ident;
    let vis = &item.vis;
    let transactions_ident = format_ident!("{trait_ident}Transactions");
    let db_ident = format_ident!("{trait_ident}Db");

    let declared = methods
        .iter()
        .filter(|method| !matches!(method.kind, Kind::Transaction))
        .map(|method| TraitItem::Fn(method.function.clone()))
        .collect();
    item.items = declared;
    let sync_methods = methods.iter().filter_map(Method::sync_impl);
    let transactions = transactions_trait(&methods, trait_ident, &transactions_ident, vis);
    let async_methods = methods
        .iter()
        .map(|method| method.async_impl(trait_ident, &transactions_ident, vis));
    let statements = methods.iter().filter_map(Method::statement);
    let doc = format!(
        "Async [`{trait_ident}`]: each call takes a connection from the database \
         and runs in its own transaction. Generated by `#[dao]`."
    );

    Ok(quote! {
        #item

        impl #trait_ident for ::rusqlite::Connection {
            #(#sync_methods)*
        }

        #transactions

        #[doc = #doc]
        #[derive(Clone)]
        #vis struct #db_ident {
            db: crate::store::Db,
        }

        #[allow(
            dead_code,
            reason = "every DAO method gets an async twin whether or not it is called"
        )]
        impl #db_ident {
            /// Every statement this DAO runs, for checking against the schema.
            #vis const QUERIES: &'static [crate::store::DaoStatement] = &[#(#statements),*];

            /// Serves this DAO from `db`.
            #vis fn new(db: crate::store::Db) -> Self {
                Self { db }
            }

            #(#async_methods)*
        }
    })
}

/// The `#[transaction]` methods, on a trait implemented only for
/// `rusqlite::Transaction`: they rely on the caller's transaction, so a bare
/// connection must not be able to call them. The bodies go on the
/// implementation, where `self` is a concrete `Transaction`, so they can call
/// any DAO in scope, including other DAOs' transaction methods.
fn transactions_trait(
    methods: &[Method],
    trait_ident: &Ident,
    transactions_ident: &Ident,
    vis: &Visibility,
) -> TokenStream2 {
    let transactions: Vec<&Method> = methods
        .iter()
        .filter(|method| matches!(method.kind, Kind::Transaction))
        .collect();
    if transactions.is_empty() {
        return TokenStream2::new();
    }
    let declarations = transactions.iter().map(|method| {
        let mut declaration = method.function.clone();
        declaration.default = None;
        declaration.semi_token = Some(Default::default());
        declaration
    });
    let bodies = transactions.iter().map(|method| {
        let sig = &method.function.sig;
        let body = &method.function.default;
        let cfgs = &method.cfgs;
        let lints = &method.lints;
        quote! {
            #(#cfgs)*
            #(#lints)*
            #sig #body
        }
    });
    let doc = format!(
        "The `#[transaction]` methods of [`{trait_ident}`], callable only inside \
         a transaction. Generated by `#[dao]`."
    );
    quote! {
        #[doc = #doc]
        #vis trait #transactions_ident {
            #(#declarations)*
        }

        impl #transactions_ident for ::rusqlite::Transaction<'_> {
            #(#bodies)*
        }
    }
}

impl Method {
    fn parse(mut function: TraitItemFn) -> syn::Result<Self> {
        let marker = take_marker(&mut function.attrs, &function.sig.ident)?;
        let name = function.sig.ident.unraw().to_string();
        if RESERVED_METHODS.contains(&name.as_str()) {
            return Err(Error::new(
                function.sig.ident.span(),
                format!(
                    "`{name}` is taken by the generated `…Db` constructor or by a `rusqlite` \
                     connection method; choose another name"
                ),
            ));
        }
        reject_type_generics(&function)?;
        let arguments = arguments(&function)?;
        let value = rusqlite_result_value(&function.sig.output)?;
        let kind = match marker {
            Marker::Query(sql) => {
                reject_body(&function, "#[query]")?;
                check_parameters(&sql, &arguments)?;
                Kind::Query {
                    rows: rows(&value)?,
                    sql,
                }
            }
            Marker::Execute(sql) => {
                reject_body(&function, "#[execute]")?;
                let scan = check_parameters(&sql, &arguments)?;
                let outcome = outcome(&value)?;
                match (&outcome, scan.returning) {
                    (Outcome::Returned(_), false) => {
                        return Err(Error::new(
                            sql.span(),
                            "an #[execute] that returns rows needs a RETURNING clause; \
                             return `usize` for the number of rows changed",
                        ));
                    }
                    (Outcome::Changed | Outcome::Nothing, true) => {
                        return Err(Error::new(
                            sql.span(),
                            "a RETURNING clause returns rows; declare the row type \
                             (`T`, `Option<T>` or `Vec<T>`) as the result",
                        ));
                    }
                    _ => {}
                }
                Kind::Execute { outcome, sql }
            }
            Marker::Transaction => {
                if function.default.is_none() {
                    return Err(Error::new(
                        function.sig.span(),
                        "a #[transaction] method needs a body; it runs as one write",
                    ));
                }
                Kind::Transaction
            }
        };
        let named = |names: &[&str]| -> Vec<Attribute> {
            function
                .attrs
                .iter()
                .filter(|attribute| names.iter().any(|name| attribute.path().is_ident(name)))
                .cloned()
                .collect()
        };
        let lint_levels = ["allow", "warn", "deny", "forbid", "expect"];
        Ok(Self {
            cfgs: named(&["cfg"]),
            twin_attributes: named(&[
                "cfg_attr",
                "deprecated",
                "allow",
                "warn",
                "deny",
                "forbid",
                "expect",
            ]),
            lints: named(&lint_levels),
            deprecated: function.attrs.iter().any(|attribute| {
                attribute.path().is_ident("deprecated")
                    || (attribute.path().is_ident("cfg_attr")
                        && quote!(#attribute).to_string().contains("deprecated"))
            }),
            function,
            kind,
            arguments,
            value,
        })
    }

    fn statement(&self) -> Option<TokenStream2> {
        let (sql, read_only) = match &self.kind {
            Kind::Query { sql, .. } => (sql, true),
            Kind::Execute { sql, .. } => (sql, false),
            Kind::Transaction => return None,
        };
        let cfgs = &self.cfgs;
        Some(quote! {
            #(#cfgs)*
            crate::store::DaoStatement { sql: #sql, read_only: #read_only }
        })
    }

    /// The `rusqlite::Connection` implementation. Transaction methods live on
    /// their own trait instead.
    fn sync_impl(&self) -> Option<TokenStream2> {
        let (sql, body) = match &self.kind {
            Kind::Query { sql, rows } => (sql, read_rows(rows)),
            Kind::Execute { sql, outcome } => (
                sql,
                match outcome {
                    Outcome::Changed => quote! { __dao_statement.execute(__dao_params) },
                    Outcome::Nothing => {
                        quote! { __dao_statement.execute(__dao_params).map(|_| ()) }
                    }
                    Outcome::Returned(rows) => read_rows(rows),
                },
            ),
            Kind::Transaction => return None,
        };
        let sig = &self.function.sig;
        let cfgs = &self.cfgs;
        let keys = self.arguments.iter().map(|argument| {
            LitStr::new(&format!(":{}", argument.sql_name()), argument.name.span())
        });
        let names = self.arguments.iter().map(|argument| &argument.name);
        Some(quote! {
            #(#cfgs)*
            #sig {
                let mut __dao_statement = self.prepare_cached(#sql)?;
                let __dao_params = ::rusqlite::named_params! { #(#keys: #names),* };
                #body
            }
        })
    }

    /// The async twin on the generated `…Db` struct.
    fn async_impl(
        &self,
        trait_ident: &Ident,
        transactions_ident: &Ident,
        vis: &Visibility,
    ) -> TokenStream2 {
        let name = &self.function.sig.ident;
        let generics = &self.function.sig.generics;
        let docs = self
            .function
            .attrs
            .iter()
            .filter(|attribute| attribute.path().is_ident("doc"));
        let cfgs = &self.cfgs;
        let twin_attributes = &self.twin_attributes;
        let allow_deprecated = self.deprecated.then(|| quote!(#[allow(deprecated)]));
        let value = &self.value;
        let parameters = self
            .arguments
            .iter()
            .map(|Argument { name, ty, .. }| quote!(#name: #ty));
        let owned = self.arguments.iter().map(
            |Argument {
                 name, ownership, ..
             }| match ownership {
                Ownership::Owned => quote!(),
                Ownership::Reference => {
                    quote!(let #name = ::std::borrow::ToOwned::to_owned(#name);)
                }
                Ownership::OptionalReference => {
                    quote!(let #name = #name.map(::std::borrow::ToOwned::to_owned);)
                }
            },
        );
        let call = self.arguments.iter().map(
            |Argument {
                 name, ownership, ..
             }| match ownership {
                Ownership::Owned => quote!(#name),
                Ownership::Reference => quote!(::std::borrow::Borrow::borrow(&#name)),
                Ownership::OptionalReference => {
                    quote!(#name.as_ref().map(::std::borrow::Borrow::borrow))
                }
            },
        );
        let (access, receiver) = match self.kind {
            Kind::Query { .. } => (
                quote!(read),
                quote!(<::rusqlite::Connection as #trait_ident>),
            ),
            Kind::Execute { .. } => (
                quote!(write),
                quote!(<::rusqlite::Connection as #trait_ident>),
            ),
            Kind::Transaction => (
                quote!(write),
                quote!(<::rusqlite::Transaction<'_> as #transactions_ident>),
            ),
        };
        quote! {
            #(#cfgs)*
            #(#twin_attributes)*
            #(#docs)*
            #vis async fn #name #generics (&self, #(#parameters),*)
                -> ::core::result::Result<#value, crate::store::DbError>
            {
                #(#owned)*
                self.db
                    .#access(move |__dao_connection| {
                        #allow_deprecated
                        let __dao_result = #receiver::#name(__dao_connection, #(#call),*);
                        __dao_result.map_err(::core::convert::Into::into)
                    })
                    .await
            }
        }
    }
}

/// Reads the statement's rows in the declared shape.
fn read_rows(rows: &Rows) -> TokenStream2 {
    match rows {
        Rows::Many(row) => quote! {
            let mut __dao_rows = __dao_statement.query(__dao_params)?;
            let mut __dao_out = ::std::vec::Vec::new();
            while let ::core::option::Option::Some(__dao_row) = __dao_rows.next()? {
                __dao_out.push(crate::store::dao_row::<#row>(__dao_row)?);
            }
            ::core::result::Result::Ok(__dao_out)
        },
        Rows::Optional(row) => quote! {
            let mut __dao_rows = __dao_statement.query(__dao_params)?;
            match __dao_rows.next()? {
                ::core::option::Option::Some(__dao_row) => {
                    crate::store::dao_row::<#row>(__dao_row).map(::core::option::Option::Some)
                }
                ::core::option::Option::None => {
                    ::core::result::Result::Ok(::core::option::Option::None)
                }
            }
        },
        Rows::One(row) => quote! {
            let mut __dao_rows = __dao_statement.query(__dao_params)?;
            match __dao_rows.next()? {
                ::core::option::Option::Some(__dao_row) => crate::store::dao_row::<#row>(__dao_row),
                ::core::option::Option::None => {
                    ::core::result::Result::Err(::rusqlite::Error::QueryReturnedNoRows)
                }
            }
        },
    }
}

enum Marker {
    Query(LitStr),
    Execute(LitStr),
    Transaction,
}

/// Removes the method's marker attribute and returns what it says.
fn take_marker(attributes: &mut Vec<Attribute>, method: &Ident) -> syn::Result<Marker> {
    let mut found = None;
    let mut error = None;
    attributes.retain(|attribute| {
        let marker = if attribute.path().is_ident("query") {
            attribute.parse_args().map(Marker::Query)
        } else if attribute.path().is_ident("execute") {
            attribute.parse_args().map(Marker::Execute)
        } else if attribute.path().is_ident("transaction") {
            Ok(Marker::Transaction)
        } else {
            return true;
        };
        match (marker, &found) {
            (Ok(marker), None) => found = Some(marker),
            (Ok(_), Some(_)) => {
                error = Some(Error::new(
                    attribute.span(),
                    "a #[dao] method takes exactly one of #[query], #[execute] or #[transaction]",
                ));
            }
            (Err(parse), _) => error = Some(parse),
        }
        false
    });
    if let Some(error) = error {
        return Err(error);
    }
    found.ok_or_else(|| {
        Error::new(
            method.span(),
            "mark each #[dao] method with #[query(\"…\")], #[execute(\"…\")] or #[transaction]",
        )
    })
}

fn reject_body(function: &TraitItemFn, marker: &str) -> syn::Result<()> {
    match &function.default {
        Some(body) => Err(Error::new(
            body.span(),
            format!("a {marker} method has no body; #[dao] writes it from the SQL"),
        )),
        None => Ok(()),
    }
}

/// Lifetimes carry over to the async twin; type and const parameters would
/// have to be `Send + 'static` and are not supported.
fn reject_type_generics(function: &TraitItemFn) -> syn::Result<()> {
    let generics = &function.sig.generics;
    if let Some(parameter) = generics
        .params
        .iter()
        .find(|parameter| !matches!(parameter, GenericParam::Lifetime(_)))
    {
        return Err(Error::new(
            parameter.span(),
            "a #[dao] method takes no type or const parameters; use concrete types",
        ));
    }
    if let Some(clause) = &generics.where_clause {
        return Err(Error::new(
            clause.span(),
            "a #[dao] method takes no where clause",
        ));
    }
    Ok(())
}

/// The method's arguments after `&self`.
fn arguments(function: &TraitItemFn) -> syn::Result<Vec<Argument>> {
    let mut inputs = function.sig.inputs.iter();
    match inputs.next() {
        Some(FnArg::Receiver(receiver))
            if receiver.reference.is_some() && receiver.mutability.is_none() => {}
        _ => {
            return Err(Error::new(
                function.sig.span(),
                "a #[dao] method takes `&self` first",
            ));
        }
    }
    inputs
        .map(|input| {
            let FnArg::Typed(typed) = input else {
                return Err(Error::new(input.span(), "unexpected receiver"));
            };
            let Pat::Ident(pattern) = typed.pat.as_ref() else {
                return Err(Error::new(typed.pat.span(), "use a plain argument name"));
            };
            if pattern.ident.unraw().to_string().starts_with("__dao_") {
                return Err(Error::new(
                    pattern.ident.span(),
                    "argument names starting with `__dao_` are reserved for generated code",
                ));
            }
            let ty = (*typed.ty).clone();
            Ok(Argument {
                ownership: ownership(&ty, &pattern.ident)?,
                name: pattern.ident.clone(),
                ty,
            })
        })
        .collect()
}

fn ownership(ty: &Type, name: &Ident) -> syn::Result<Ownership> {
    let borrows = |ty: &Type| {
        let tokens = quote!(#ty).to_string();
        tokens.contains('&') || tokens.contains('\'')
    };
    let unsupported = || {
        Error::new(
            ty.span(),
            format!(
                "argument `{}` borrows in a way the async twin cannot own; \
                 use an owned type, `&T` or `Option<&T>`",
                name.unraw()
            ),
        )
    };
    if matches!(ty, Type::ImplTrait(_)) {
        return Err(Error::new(
            ty.span(),
            "a #[dao] argument takes a concrete type, not `impl Trait`",
        ));
    }
    if let Type::Reference(reference) = ty {
        if reference.mutability.is_some() {
            return Err(Error::new(ty.span(), "a #[dao] argument cannot be `&mut`"));
        }
        if borrows(&reference.elem) {
            return Err(unsupported());
        }
        return Ok(Ownership::Reference);
    }
    if let Some(("Option", Type::Reference(reference))) = container(ty)
        && reference.mutability.is_none()
        && !borrows(&reference.elem)
    {
        return Ok(Ownership::OptionalReference);
    }
    if borrows(ty) {
        return Err(unsupported());
    }
    Ok(Ownership::Owned)
}

/// `T` from a declared `rusqlite::Result<T>`.
fn rusqlite_result_value(output: &ReturnType) -> syn::Result<Type> {
    let error = |span| Error::new(span, "a #[dao] method returns `rusqlite::Result<…>`");
    let ReturnType::Type(_, ty) = output else {
        return Err(error(output.span()));
    };
    let Type::Path(path) = ty.as_ref() else {
        return Err(error(ty.span()));
    };
    let segments: Vec<_> = path.path.segments.iter().collect();
    let [crate_segment, result] = segments.as_slice() else {
        return Err(error(ty.span()));
    };
    if crate_segment.ident != "rusqlite" || result.ident != "Result" {
        return Err(error(ty.span()));
    }
    single_generic(&result.arguments).ok_or_else(|| error(ty.span()))
}

fn rows(value: &Type) -> syn::Result<Rows> {
    Ok(match container(value) {
        Some(("Vec", row)) => {
            if matches!(&row, Type::Path(path)
                if path.path.segments.last().is_some_and(|last| last.ident == "u8"))
            {
                return Err(Error::new(
                    value.span(),
                    "`Vec<u8>` would read one byte per row; for a blob column return a row \
                     struct with `#[serde(with = \"serde_bytes\")]`, or `Vec<Vec<u8>>` for many",
                ));
            }
            Rows::Many(Box::new(row))
        }
        Some(("Option", row)) => Rows::Optional(Box::new(row)),
        _ => Rows::One(Box::new(value.clone())),
    })
}

fn outcome(value: &Type) -> syn::Result<Outcome> {
    match value {
        Type::Tuple(tuple) if tuple.elems.is_empty() => Ok(Outcome::Nothing),
        Type::Path(path) if path.path.is_ident("usize") => Ok(Outcome::Changed),
        other => Ok(Outcome::Returned(rows(other)?)),
    }
}

/// `("Vec", T)` for `Vec<T>`, `("Option", T)` for `Option<T>`.
fn container(ty: &Type) -> Option<(&'static str, Type)> {
    let Type::Path(path) = ty else { return None };
    let last = path.path.segments.last()?;
    let name = ["Vec", "Option"]
        .into_iter()
        .find(|name| last.ident == name)?;
    Some((name, single_generic(&last.arguments)?))
}

fn single_generic(arguments: &PathArguments) -> Option<Type> {
    let PathArguments::AngleBracketed(arguments) = arguments else {
        return None;
    };
    match arguments.args.iter().collect::<Vec<_>>().as_slice() {
        [GenericArgument::Type(ty)] => Some(ty.clone()),
        _ => None,
    }
}

/// Every `:name` in the SQL must be an argument, and every argument a `:name`.
fn check_parameters(sql: &LitStr, arguments: &[Argument]) -> syn::Result<Scan> {
    let scan = scan(&sql.value()).map_err(|message| Error::new(sql.span(), message))?;
    if let Some(unbound) = scan.parameters.iter().find(|name| {
        !arguments
            .iter()
            .any(|argument| argument.sql_name() == **name)
    }) {
        return Err(Error::new(
            sql.span(),
            format!("`:{unbound}` has no argument with that name"),
        ));
    }
    if let Some(unused) = arguments
        .iter()
        .find(|argument| !scan.parameters.contains(&argument.sql_name()))
    {
        return Err(Error::new(
            unused.name.span(),
            format!("argument `{}` is not used in the SQL", unused.sql_name()),
        ));
    }
    Ok(scan)
}

/// What the macro needs to know about a statement's text.
#[derive(Debug, Default)]
struct Scan {
    /// `:name` parameters.
    parameters: BTreeSet<String>,
    /// Whether a `RETURNING` keyword appears.
    returning: bool,
}

/// SQLite's identifier characters: ASCII alphanumerics, `_`, `$`, and
/// anything outside ASCII.
fn is_identifier_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '$' || !c.is_ascii()
}

/// Tokenizes `sql` the way SQLite does for the parts that matter here,
/// skipping string literals, quoted identifiers and comments.
fn scan(sql: &str) -> Result<Scan, &'static str> {
    let mut scan = Scan::default();
    let mut chars = sql.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\'' | '"' | '`' => {
                for inner in chars.by_ref() {
                    if inner == c {
                        break;
                    }
                }
            }
            '[' => {
                for inner in chars.by_ref() {
                    if inner == ']' {
                        break;
                    }
                }
            }
            '-' if chars.peek() == Some(&'-') => {
                for inner in chars.by_ref() {
                    if inner == '\n' {
                        break;
                    }
                }
            }
            '/' if chars.peek() == Some(&'*') => {
                chars.next();
                let mut previous = None;
                for inner in chars.by_ref() {
                    if previous == Some('*') && inner == '/' {
                        break;
                    }
                    previous = Some(inner);
                }
            }
            '?' | '@' | '$' | '#' => {
                return Err("use `:name` parameters, bound from the method's arguments");
            }
            ':' => {
                let mut name = String::new();
                loop {
                    match chars.peek() {
                        Some(&next) if is_identifier_char(next) => {
                            name.push(next);
                            chars.next();
                        }
                        Some(':') if !name.is_empty() => {
                            let mut lookahead = chars.clone();
                            lookahead.next();
                            if lookahead.peek() != Some(&':') {
                                break;
                            }
                            name.push_str("::");
                            chars.next();
                            chars.next();
                        }
                        _ => break,
                    }
                }
                if !name.is_empty() {
                    if chars.peek() == Some(&'(') {
                        return Err("SQLite reads `:name(…)` as one parameter; add a space \
                                    before `(`");
                    }
                    scan.parameters.insert(name);
                }
            }
            c if is_identifier_char(c) => {
                let mut word = String::from(c);
                while let Some(&next) = chars.peek() {
                    if !is_identifier_char(next) {
                        break;
                    }
                    word.push(next);
                    chars.next();
                }
                if word.eq_ignore_ascii_case("returning") {
                    scan.returning = true;
                }
            }
            _ => {}
        }
    }
    Ok(scan)
}

#[cfg(test)]
mod tests {
    use super::scan;

    fn names(sql: &str) -> Vec<String> {
        scan(sql).unwrap().parameters.into_iter().collect()
    }

    #[test]
    fn finds_each_named_parameter_once() {
        assert_eq!(
            names("SELECT * FROM t WHERE a = :a AND b > :b_2 OR a = :a"),
            vec!["a".to_owned(), "b_2".to_owned()]
        );
    }

    #[test]
    fn ignores_colons_inside_literals_identifiers_and_comments() {
        // A `:word` in a string or comment is text, not a parameter; binding
        // it would fail at runtime.
        let sql = "SELECT ':x', \"col:y\", [z:w] FROM t -- :comment\n WHERE a = :a /* :b */";
        assert_eq!(names(sql), vec!["a".to_owned()]);
    }

    #[test]
    fn rejects_every_non_colon_parameter_form() {
        // SQLite treats all of these as parameters, and an unbound one is NULL.
        for sql in ["a = ?1", "a = ?", "a = @a", "a = $a", "a = :a OR a = #a"] {
            assert!(scan(sql).is_err(), "{sql}");
        }
    }

    #[test]
    fn names_follow_sqlite_identifier_rules() {
        // `$` and non-ASCII characters continue a name and `::` joins two
        // parts, as in SQLite's tokenizer; an unquoted identifier may hold `$`.
        let sql = "SELECT x$y FROM t WHERE a = :a$b AND b = :café AND c = :c::d AND d = :e:f";
        assert_eq!(
            names(sql),
            vec![
                "a$b".to_owned(),
                "c::d".to_owned(),
                "café".to_owned(),
                "e".to_owned(),
                "f".to_owned(),
            ]
        );
    }

    #[test]
    fn rejects_a_tcl_style_parameter_suffix() {
        // SQLite reads `:a(x)` as one parameter named `:a(x)`, not `:a`.
        assert!(scan("SELECT * FROM t WHERE a = :a(x)").is_err());
    }

    #[test]
    fn notices_a_returning_clause_outside_literals() {
        assert!(
            scan("INSERT INTO t (a) VALUES (1) RETURNING id")
                .unwrap()
                .returning
        );
        assert!(
            !scan("INSERT INTO t (a) VALUES ('RETURNING')")
                .unwrap()
                .returning
        );
    }
}
