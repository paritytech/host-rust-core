---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Add the `Motion` device permission. Products request it through `authorizeDevicePermission("Motion")` or the standard `DeviceMotionEvent.requestPermission()`, and the host answers WebKit's motion request from the product's saved, one-use, or prompted decision.
