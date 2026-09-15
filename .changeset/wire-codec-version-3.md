---
"@parity/truapi": major
---

The wire codec version is 3. Seven frame legs change shape, so a peer built against codec 2 is
refused at the handshake rather than failing per call when the first mismatched frame arrives.
Hosts and products negotiate this at connect time and need no coordinated deploy.
