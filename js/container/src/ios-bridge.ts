// =============================================================================
// iOS WKScriptMessageHandler bridge — the only module that touches
// window.webkit.
//
// The container runs in the product's own realm, so the reply callback is
// reachable by product code. A forged reply requires a valid (id, payload)
// pair; the shared hardening closes the three id-leak channels:
//   - unguessable ids (native-transport uses 128-bit crypto ids);
//   - the native postMessage is captured at init, before product scripts run,
//     so a later Proxy over window.webkit cannot observe outbound ids;
//   - the reply callback is frozen (installNativeBridge) so it cannot be
//     wrapped to read the inbound id.
// =============================================================================

import { HANDLER_NAME, installNativeBridge } from './bridge-contract.js';
import type { NativeTransport } from './native-transport.js';

interface WebKitMessageHandler {
  postMessage(message: unknown): void;
}

interface WebKitBridge {
  messageHandlers?: Record<string, WebKitMessageHandler | undefined>;
}

function getMessageHandler(): WebKitMessageHandler | undefined {
  const webkit = (window as unknown as { webkit?: WebKitBridge }).webkit;
  return webkit?.messageHandlers?.[HANDLER_NAME];
}

/**
 * Builds the native bridge transport over the iOS WKScriptMessageHandler, or
 * `undefined` when the handler is absent. Captures postMessage before any
 * product script can wrap it.
 */
export function createIOSBridge(): NativeTransport | undefined {
  const handler = getMessageHandler();
  if (handler === undefined) {
    return undefined;
  }

  // Capture native postMessage now, before any product script can wrap it.
  const postMessage = handler.postMessage.bind(handler);
  return installNativeBridge((message) => {
    postMessage(message);
  });
}
