---
title: "Host locale subscription"
owner: "@kalininilya"
status: draft
---

# RFC — Host locale subscription

## Summary

Add `locale.subscribe()`, a subscription that pushes the language the host
currently presents its own interface in. Products render in that language
instead of guessing one.

```ts
const locale = await firstValueFrom(from(truapi.locale.subscribe()));

locale.languageTag;
// "zh-Hans"
```

## Motivation

A product has no way to learn the language its host is running in.
`navigator.language` reports the operating system's preference, which is the
wrong answer whenever the user picked a different language inside the host —
the common case, since that setting exists precisely because the OS value did
not suit them. The result is host chrome in one language wrapped around a
product in another.

getCash.dot ships in the 4 September release and needs the selected language to
render its own strings. It is the only product in that release, so the gap is
concrete today and there is no product-side workaround that produces the right
answer.

## Approach

A subscription, matching `theme.subscribe()`: the host emits its current locale
immediately, then again on every change. Locale is user-agent state that changes
while a product is running, so a one-shot read would leave products stale after
a language switch.

```rust
struct HostLocaleSubscribeItem {
    /// BCP 47 language tag.
    pub language_tag: String,
}
```

`language_tag` is a BCP 47 tag: `en`, `pt-BR`, `zh-Hans`. The set is open rather
than an enum of shipped languages, so a host adds a language without a protocol
change and without every other host having to recompile against a wider type. A
product that does not ship the tag it receives picks its own fallback; the host
does not negotiate one, because it cannot know what a product translated.

No permission gate and no pairing requirement. The selected language is not
user data a product could not otherwise observe — it is already visible in the
rendered chrome around it — and a product needs it on first paint, before any
account exists.

`LocaleHost` joins the required `Platform` set alongside `ThemeHost`, so every
host serves a real value rather than reporting the method unsupported and
sending every product down a fallback path.

## Trade-offs

- Every host must implement one more callback. It is a required trait, not an
  optional capability, which is what makes the value trustworthy — the
  alternative is a protocol that is present but answers `Unsupported` on the
  host a product happens to run in.
- The open tag means a product can receive a language it does not ship. That is
  true of any real i18n surface, and the fallback belongs to the product, which
  is the only party that knows its own catalog.
- Text direction is not carried. It is derivable from the tag
  (`Intl.Locale.prototype.textInfo`), and duplicating it invites the two fields
  to disagree.

## Alternatives

A closed enum of supported languages was rejected: every new language in any
host becomes a wire-breaking change across rust-core and all five hosts.

Extending `HostThemeSubscribeItem` with a language field was rejected: theme and
language change independently and are consumed by different parts of a product,
so a shared subscription wakes both paths on either change.
