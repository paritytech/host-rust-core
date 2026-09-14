---
"@parity/truapi": patch
---

The unprefixed name for a versioned type belongs to the newest version any wrapper selects. Where several wrappers
name one base type at different versions — `HostLocalStorageClearError` and `HostLocalStorageWriteError` on V1 while
`HostLocalStorageReadError` is on V2 — `HostLocalStorageReadError` is the v02 shape and `V01HostLocalStorageReadError`
carries the v01 one.
