// =============================================================================
// Android WebView bridge — the only module that touches window.Android, the
// @JavascriptInterface object exposing `call(functionName, argsJson)`.
//
// Same same-realm hardening as the iOS bridge: unguessable ids (native-transport),
// the `Android.call` reference captured at init before product scripts run, and
// the frozen reply callback (installNativeBridge).
// =============================================================================

import { HANDLER_NAME, installNativeBridge } from './bridge-contract.js';
import type { NativeTransport } from './native-transport.js';

interface AndroidBridge {
  call(functionName: string, argsJson: string): string;
}

function getAndroid(): AndroidBridge | undefined {
  const android = (window as unknown as { Android?: AndroidBridge }).Android;
  return typeof android?.call === 'function' ? android : undefined;
}

/**
 * Builds the native bridge transport over the Android WebView
 * JavascriptInterface, or `undefined` when it is absent. Captures `Android.call`
 * before any product script can wrap it.
 */
export function createAndroidBridge(): NativeTransport | undefined {
  const android = getAndroid();
  if (android === undefined) {
    return undefined;
  }

  // Capture Android.call now, before any product script can wrap it.
  const call = android.call.bind(android);
  return installNativeBridge((message) => {
    call(HANDLER_NAME, message);
  });
}
