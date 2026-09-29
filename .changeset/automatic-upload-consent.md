---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

`resource_allocation.request` accepts `AutomaticUpload`, a consent for `preimage.submit` to upload without asking the user each time. The host stores it for the requesting product and the session's root account as `PermissionAuthorizationRequest::AutomaticUpload { root_public_key }`, and never forwards it to the signing host. While it holds, uploads of at most 256 KiB, up to 4 per product and account in any hour, skip the per-upload confirmation. Larger or more frequent uploads still ask. Setting the permission back to `NotDetermined` revokes it. Hosts that match exhaustively on `AllocatableResource` or `PermissionAuthorizationRequest` need an arm for the new variants.
