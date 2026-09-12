---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

`Renderer` is the one service through which a product draws a body inside a host surface. The host starts
`renderer.onRender` with a `RenderContext` (`ChatMessage`, `InputWidget`, `PocketCard`) and an opaque payload; the
product streams `RendererNode` trees, and a press inside a tree reaches `renderer.actionSubscribe` as
`{ context, actionId, payload }`. `Chat` has no `custom_message_render`; a `Custom` chat message renders through
`Renderer` with a `ChatMessage` context, and `ChatActionPayload.ActionTriggered` carries only host-drawn `Actions`
button presses.

`RendererNode` replaces `CustomRendererNode` with `Image` (`ImageSource`, `ImageFit`), `Effect`, `Shape.Square`,
`Modifier.Opacity` and `Modifier.BlendingMode`; `Spacer`, `TextField` and `Image` carry no `children`, and single-field
variants are tuple variants.

Hosts call `provider.render(request, sink)` and `provider.publishRendererAction(item)`; `publishChatAction` remains for
posted messages, commands and host-drawn `Actions` buttons.
