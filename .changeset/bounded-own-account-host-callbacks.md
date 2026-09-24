---
"@parity/truapi": patch
"@parity/truapi-host": patch
---

`account.get_account` no longer waits forever on a host that does not answer.

Resolving a product's own account reads a stored subtree through the host and
then asks the host to confirm. Neither call had a deadline, so a host whose
storage never answered left the request parked with no response and no error.
Both now take the caller's deadline, falling back to the same default the SSO
call below them uses, and an unresponsive host gets a typed
`HostAccountGetError` instead.
