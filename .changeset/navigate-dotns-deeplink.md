---
"@parity/truapi-host": major
---

`navigate_to` hands a host a dotNS product destination as `polkadot://<product_id>.<tld>/<path>` rather than rewriting
it to `https://`. That is the form the Pocket deeplink grammar already defines for a product URL, and the one a Pocket
target already arrives as, so a host routes on the scheme instead of guessing from the domain. An `http(s)` destination
is unchanged and still gated on a per-host grant.

A host that recognised `https://<name>.<tld>` and converted it back should match `polkadot://` instead.
