// =============================================================================
// Shared native-bridge contract.
//
// The handler/callback names both platforms use, plus the wiring that turns a
// platform `send` into a NativeTransport with the frozen reply dispatcher
// installed. The per-platform bridges (ios-bridge, android-bridge) differ only
// in how they capture their outbound channel; everything downstream is shared.
// =============================================================================

import { freezeValue } from './freeze.js';
import { createNativeTransport } from './native-transport.js';
import type { NativeSender, NativeTransport } from './native-transport.js';

/** Handler/function name both platforms expose for the container bridge. */
export const HANDLER_NAME = '__container__';

/** Global the native side invokes with a request id and JSON reply payload. */
export const CALLBACK_NAME = '__container_callback__';

/**
 * Builds a native transport over `send` and installs the frozen reply
 * dispatcher the native side invokes. Shared by the per-platform bridges; call
 * at most once (the frozen callback can only be installed once).
 */
export function installNativeBridge(send: NativeSender): NativeTransport {
  const transport = createNativeTransport(send);
  freezeValue(window, CALLBACK_NAME, (id: string, payloadJson: string) => {
    transport.dispatch(id, payloadJson);
  });
  return transport;
}
