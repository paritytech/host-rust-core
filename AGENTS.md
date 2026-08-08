# Agent guidance

- After a PR has been opened or submitted, make follow-up changes as normal commits. Do not rewrite existing commits or force-push unless explicitly requested.
- Do not mirror canonical Rust domain or protocol types with `Native*` FFI copies. Export the canonical type with feature-gated UniFFI derives and custom conversions for unsupported leaf values. Keep boundary-specific types only when they model native lifecycle or behavior rather than duplicate data.
