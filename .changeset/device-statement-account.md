---
"@parity/truapi": minor
---

Host applications running their own statement-store traffic reach the account the paired wallet granted an allowance to:
`SessionUiInfo.deviceStatementAccountId` carries the id and `CoreAdmin.getDeviceStatementKey` the sr25519 secret behind
it. A signing host also answers `Pending(AllowanceAllocation)` before allocating the device slot, so a pairing host
shows progress instead of an already-scanned QR, and `Failed(reason)` if the allocation then fails.
