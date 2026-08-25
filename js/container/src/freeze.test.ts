import { beforeEach, describe, expect, it } from 'bun:test';

import {
  freezeAndDelete,
  freezeCustom,
  freezeValue,
  lockdownFailures,
  reportLockdownFailures,
  resetLockdownFailures,
} from './freeze.js';

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * An object whose `prop` cannot be locked: non-configurable defeats
 * `defineProperty`, and the module's strict mode makes the `delete` fallback
 * throw. This is the shape that used to fail silently.
 */
function unlockable(prop: string, value: unknown): any {
  const obj: any = {};
  Object.defineProperty(obj, prop, { value, configurable: false, writable: false });
  return obj;
}

beforeEach(() => {
  resetLockdownFailures();
});

describe('a lock that takes', () => {
  it('records nothing when the property reads as undefined', () => {
    const win: any = { RTCPeerConnection: class {} };
    freezeAndDelete(win, 'RTCPeerConnection');
    expect(win.RTCPeerConnection).toBeUndefined();
    expect(lockdownFailures()).toEqual([]);
  });

  it('records nothing when the property reads as the pinned value', () => {
    const win: any = { fetch: () => {} };
    const gated = () => {};
    freezeValue(win, 'fetch', gated);
    expect(win.fetch).toBe(gated);
    expect(lockdownFailures()).toEqual([]);
  });

  it('records nothing when a custom verify accepts the result', () => {
    const doc: any = { cookie: 'session=1' };
    freezeCustom(doc, 'cookie', { get: () => '', set: () => {} }, (c) => c === '');
    expect(doc.cookie).toBe('');
    expect(lockdownFailures()).toEqual([]);
  });

  it('reports nothing to throw about', () => {
    expect(() => reportLockdownFailures()).not.toThrow();
  });
});

describe('a lock that does not take', () => {
  // The gap this reporting exists to close: `defineProperty` threw, `delete`
  // threw, and the constructor stayed reachable with nobody the wiser.
  it('is recorded when the constructor survives freezeAndDelete', () => {
    const Native = class {};
    const win = unlockable('RTCPeerConnection', Native);
    freezeAndDelete(win, 'RTCPeerConnection');
    expect(win.RTCPeerConnection).toBe(Native);
    expect(lockdownFailures()).toEqual(['Object.RTCPeerConnection']);
  });

  it('is recorded when freezeValue cannot replace the property', () => {
    const win = unlockable('fetch', () => 'native');
    freezeValue(win, 'fetch', () => 'gated');
    expect(lockdownFailures()).toEqual(['Object.fetch']);
  });

  it('is recorded when a custom verify rejects the result', () => {
    const doc = unlockable('cookie', 'session=1');
    freezeCustom(doc, 'cookie', { get: () => '', set: () => {} }, (c) => c === '');
    expect(lockdownFailures()).toEqual(['Object.cookie']);
  });

  it('is recorded when the verify itself throws', () => {
    const obj = unlockable('boom', 1);
    freezeCustom(obj, 'boom', { value: 2, writable: false }, () => {
      throw new Error('unreadable');
    });
    expect(lockdownFailures()).toEqual(['Object.boom']);
  });

  it('accumulates every failure in order rather than stopping at the first', () => {
    // Throwing mid-sequence would skip the remaining locks and widen the hole,
    // so each one is still attempted.
    freezeAndDelete(unlockable('RTCPeerConnection', class {}), 'RTCPeerConnection');
    freezeAndDelete(unlockable('XMLHttpRequest', class {}), 'XMLHttpRequest');
    expect(lockdownFailures()).toEqual([
      'Object.RTCPeerConnection',
      'Object.XMLHttpRequest',
    ]);
  });

  it('throws from the report, naming the property, so the host learns', () => {
    freezeAndDelete(unlockable('RTCPeerConnection', class {}), 'RTCPeerConnection');
    expect(() => reportLockdownFailures()).toThrow(/RTCPeerConnection/);
  });

  it('logs before throwing, since a host may only see that evaluation failed', () => {
    const original = console.error;
    const logged: unknown[] = [];
    console.error = (...args: unknown[]) => { logged.push(args[0]); };
    try {
      freezeAndDelete(unlockable('EventSource', class {}), 'EventSource');
      expect(() => reportLockdownFailures()).toThrow();
    } finally {
      console.error = original;
    }
    expect(String(logged[0])).toContain('Object.EventSource');
  });
});
