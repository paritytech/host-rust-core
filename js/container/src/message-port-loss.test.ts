import { describe, expect, it } from 'bun:test';

import { reloadAfterMessagePortLoss } from './message-port-loss.js';

type Status = 'connecting' | 'connected' | 'disconnected';

function page(visibility: 'visible' | 'hidden') {
  const timers = new Map<number, { callback: () => void; due: number }>();
  let nextTimer = 1;
  let now = 0;
  const visibilityListeners = new Set<() => void>();
  const statusListeners = new Set<(status: Status) => void>();
  let reloads = 0;
  const win = {
    document: {
      visibilityState: visibility,
      addEventListener(type: string, listener: () => void) {
        if (type === 'visibilitychange') visibilityListeners.add(listener);
      },
      removeEventListener(type: string, listener: () => void) {
        if (type === 'visibilitychange') visibilityListeners.delete(listener);
      },
    },
    location: { reload: () => { reloads += 1; } },
    performance: { now: () => now },
    setTimeout(callback: () => void, ms: number) {
      timers.set(nextTimer, { callback, due: now + ms });
      return nextTimer++;
    },
    clearTimeout(id: number | undefined) {
      if (id !== undefined) timers.delete(id);
    },
  };
  return {
    win,
    subscribeConnectionStatus(callback: (status: Status) => void) {
      statusListeners.add(callback);
      return () => statusListeners.delete(callback);
    },
    setStatus(status: Status) {
      for (const listener of statusListeners) listener(status);
    },
    setVisibility(next: 'visible' | 'hidden') {
      win.document.visibilityState = next;
      for (const listener of visibilityListeners) listener();
    },
    async expireProbe({ lateBy = 0 } = {}) {
      // Let a live port deliver before the probe deadline is forced.
      await new Promise((resolve) => setTimeout(resolve, 20));
      for (const [id, timer] of [...timers]) {
        timers.delete(id);
        now = timer.due + lateBy;
        timer.callback();
      }
    },
    reloads: () => reloads,
  };
}

describe('reloadAfterMessagePortLoss', () => {
  // WebKit disentangles every existing MessagePort when its networking process
  // dies, and a channel created before the loss never delivers again; only a
  // reload replaces it.
  it('reloads a page whose MessagePorts died with the host connection', async () => {
    const host = page('visible');
    const canary = new MessageChannel();
    reloadAfterMessagePortLoss(host.win, host.subscribeConnectionStatus, canary);

    canary.port1.close();
    host.setStatus('disconnected');
    await host.expireProbe();

    expect(host.reloads()).toBe(1);
  });

  // A lost socket alone leaves every port working; the transport reconnects and
  // the page keeps its state.
  it('keeps a page whose MessagePorts survive a disconnect', async () => {
    const host = page('visible');
    const canary = new MessageChannel();
    reloadAfterMessagePortLoss(host.win, host.subscribeConnectionStatus, canary);

    host.setStatus('disconnected');
    await host.expireProbe();

    expect(host.reloads()).toBe(0);
    canary.port1.close();
  });

  // A suspended page cannot answer in time, so its probe waits for the page to
  // return to the foreground, which is also when WebKit's loss becomes visible.
  it('probes a hidden page once it becomes visible', async () => {
    const host = page('hidden');
    const canary = new MessageChannel();
    reloadAfterMessagePortLoss(host.win, host.subscribeConnectionStatus, canary);

    canary.port1.close();
    host.setStatus('disconnected');
    await host.expireProbe();
    const whileHidden = host.reloads();
    host.setVisibility('visible');
    await host.expireProbe();

    expect([whileHidden, host.reloads()]).toEqual([0, 1]);
  });

  // A main thread blocked past the deadline fires it late, possibly ahead of the
  // canary's queued reply, so the page probes again before deciding.
  it('probes again when the deadline fires late', async () => {
    const host = page('visible');
    const canary = new MessageChannel();
    reloadAfterMessagePortLoss(host.win, host.subscribeConnectionStatus, canary);

    canary.port1.close();
    host.setStatus('disconnected');
    await host.expireProbe({ lateBy: 500 });
    const afterLateDeadline = host.reloads();
    await host.expireProbe();

    expect([afterLateDeadline, host.reloads()]).toEqual([0, 1]);
  });

  // A page being torn down disposes its connection, which may still report a
  // disconnect; reloading it then would revive a page the user left.
  it('stops probing once stopped', async () => {
    const host = page('visible');
    const canary = new MessageChannel();
    const stop = reloadAfterMessagePortLoss(host.win, host.subscribeConnectionStatus, canary);

    canary.port1.close();
    host.setStatus('disconnected');
    stop();
    host.setStatus('disconnected');
    host.setVisibility('visible');
    await host.expireProbe();

    expect(host.reloads()).toBe(0);
  });
});
