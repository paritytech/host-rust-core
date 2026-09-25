import type { HostConnection } from '@parity/truapi/internal';

// A live port delivers within one task; the margin only absorbs a busy main thread.
const PROBE_TIMEOUT_MS = 1000;
// A deadline this late means the main thread was blocked, and the canary's reply may
// still be queued behind it.
const LATE_DEADLINE_MS = 250;

interface ProbedWindow {
  document: {
    visibilityState: DocumentVisibilityState;
    addEventListener(type: 'visibilitychange', listener: () => void): void;
    removeEventListener(type: 'visibilitychange', listener: () => void): void;
  };
  location: { reload(): void };
  performance: { now(): number };
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(id: number | undefined): void;
}

/**
 * Reload the page once WebKit has disentangled its MessagePorts.
 *
 * WebKit brokers every MessagePort through its networking process. Losing that
 * process closes every existing port without an error or an event, while ports
 * created afterwards work. The host connection recovers on its own, but a
 * channel created before the loss never delivers again. A canary channel
 * created with the container tells that loss apart from a plain socket loss,
 * which keeps the page. Returns a function that stops watching.
 */
export function reloadAfterMessagePortLoss(
  win: ProbedWindow,
  subscribeConnectionStatus: HostConnection['subscribeConnectionStatus'],
  canary: MessageChannel = new MessageChannel(),
): () => void {
  let deadline: number | undefined;

  // Listening only while probing, since a port with a listener keeps script
  // hosts such as Bun alive.
  function settle(): void {
    win.clearTimeout(deadline);
    deadline = undefined;
    canary.port1.onmessage = null;
  }

  function check(): void {
    if (deadline !== undefined || win.document.visibilityState !== 'visible') return;
    const due = win.performance.now() + PROBE_TIMEOUT_MS;
    deadline = win.setTimeout(() => {
      settle();
      if (win.performance.now() - due > LATE_DEADLINE_MS) check();
      else win.location.reload();
    }, PROBE_TIMEOUT_MS);
    canary.port1.onmessage = settle;
    canary.port2.postMessage(null);
  }

  const unsubscribe = subscribeConnectionStatus((status) => {
    if (status === 'disconnected') check();
  });
  win.document.addEventListener('visibilitychange', check);
  return () => {
    settle();
    unsubscribe();
    win.document.removeEventListener('visibilitychange', check);
  };
}
