---
"@parity/truapi": patch
---

The generated client stamps `TRUAPI_CODEC_VERSION` from `truapi::WIRE_CODEC_VERSION`, so it speaks
the codec version `system.handshake()` accepts. A client advertising any other codec is answered
with `UnsupportedProtocolVersion` on the first frame it sends, before a product reaches any other
method.
