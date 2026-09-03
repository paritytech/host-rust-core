# Repository agent guidance

## Rust style

- Prefer `derive_more::Display` over a handwritten `fmt::Display`
  implementation when the formatting is declarative. Use a manual
  implementation only when deriving cannot express the behavior cleanly.
