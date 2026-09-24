import type { HostConnection } from '@parity/truapi/internal';

// A live port delivers within one task; the margin only absorbs a busy main thread.
const PROBE_TIMEOUT_MS = 1000;

interface ProbedWindow {
  document: {
    visibilityState: DocumentVisibilityState;
    addEventListener(type: 'visibilitychange', listener: () => void): void;
  };
  location: { reload(): void };
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

/**
 * Reload the page once WebKit has disentangled its MessagePorts.
 *
 * WebKit brokers every MessagePort through its networking process. Losing that
 * process closes every existing port without an error or an event, while ports
 * created afterwards work. The host connection recovers on its own, but a
 * channel created before the loss never delivers again. A canary channel
 * created with the container tells that loss apart from a plain socket loss,
 * which keeps the page.
 */
export function reloadAfterMessagePortLoss(
  win: ProbedWindow,
  subscribeConnectionStatus: HostConnection['subscribeConnectionStatus'],
  canary: MessageChannel = new MessageChannel(),
): void {
  let probing = false;

  // Listening only while probing, since a port with a listener keeps script
  // hosts such as Bun alive.
  function check(): void {
    if (probing || win.document.visibilityState !== 'visible') return;
    probing = true;
    const stop = () => {
      canary.port1.onmessage = null;
      probing = false;
    };
    const deadline = win.setTimeout(() => {
      stop();
      win.location.reload();
    }, PROBE_TIMEOUT_MS);
    canary.port1.onmessage = () => {
      win.clearTimeout(deadline);
      stop();
    };
    canary.port2.postMessage(null);
  }

  subscribeConnectionStatus((status) => {
    if (status === 'disconnected') check();
  });
  win.document.addEventListener('visibilitychange', check);
}
