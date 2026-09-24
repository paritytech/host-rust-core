import { describe, expect, it } from 'bun:test';

import { reloadAfterMessagePortLoss } from './message-port-loss.js';

type Status = 'connecting' | 'connected' | 'disconnected';

function page(visibility: 'visible' | 'hidden') {
  const timers = new Map<number, () => void>();
  let nextTimer = 1;
  const visibilityListeners: (() => void)[] = [];
  const statusListeners: ((status: Status) => void)[] = [];
  let reloads = 0;
  const win = {
    document: {
      visibilityState: visibility,
      addEventListener(type: string, listener: () => void) {
        if (type === 'visibilitychange') visibilityListeners.push(listener);
      },
    },
    location: { reload: () => { reloads += 1; } },
    setTimeout(callback: () => void) {
      timers.set(nextTimer, callback);
      return nextTimer++;
    },
    clearTimeout(id: number) {
      timers.delete(id);
    },
  };
  return {
    win,
    subscribeConnectionStatus(callback: (status: Status) => void) {
      statusListeners.push(callback);
      return () => {};
    },
    setStatus(status: Status) {
      for (const listener of statusListeners) listener(status);
    },
    setVisibility(next: 'visible' | 'hidden') {
      win.document.visibilityState = next;
      for (const listener of visibilityListeners) listener();
    },
    async expireProbe() {
      // Let a live port deliver before the probe deadline is forced.
      await new Promise((resolve) => setTimeout(resolve, 20));
      for (const callback of [...timers.values()]) callback();
      timers.clear();
    },
    reloads: () => reloads,
  };
}

describe('reloadAfterMessagePortLoss', () => {
  // WebKit disentangles every existing MessagePort when its networking process
  // dies. Frameworks such as React schedule rendering through a MessageChannel
  // created at load, so the page stops rendering and only a reload restores it.
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
  // the product keeps its state.
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
});
