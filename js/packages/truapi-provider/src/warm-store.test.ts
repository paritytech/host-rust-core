import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { IDBFactory } from "fake-indexeddb";

import {
  DEFAULT_WARM_STORE_DATABASE_NAME,
  WarmStoreError,
  openIndexedDbWarmStore,
  startWarmStartPersistence,
} from "./warm-store.ts";

const GENESIS =
  "0x374057be67b355151f271ff70c3db98308c62c8adc48dc6724b6a009a1a014fd";
const OTHER_GENESIS = `0x${"ab".repeat(32)}`;

let savedFactory: IDBFactory | undefined;

beforeEach(() => {
  savedFactory = globalThis.indexedDB;
  globalThis.indexedDB = new IDBFactory();
});

afterEach(() => {
  if (savedFactory === undefined) {
    delete (globalThis as { indexedDB?: IDBFactory }).indexedDB;
  } else {
    globalThis.indexedDB = savedFactory;
  }
});

describe("openIndexedDbWarmStore", () => {
  test("a blob survives a reopen, which is the whole point", async () => {
    const first = openIndexedDbWarmStore();
    await first.save(GENESIS, "finalized-state");
    first.close();

    const second = openIndexedDbWarmStore();
    expect(await second.load(GENESIS)).toBe("finalized-state");
    second.close();
  });

  test("an unknown chain reads as absent, not as a failure", async () => {
    const store = openIndexedDbWarmStore();
    expect(await store.load(GENESIS)).toBeNull();
    store.close();
  });

  test("blobs are kept per chain", async () => {
    const store = openIndexedDbWarmStore();
    await store.save(GENESIS, "one");
    await store.save(OTHER_GENESIS, "two");
    expect(await store.load(GENESIS)).toBe("one");
    expect(await store.load(OTHER_GENESIS)).toBe("two");
    store.close();
  });

  test("a later save replaces the earlier blob", async () => {
    const store = openIndexedDbWarmStore();
    await store.save(GENESIS, "older");
    await store.save(GENESIS, "newer");
    expect(await store.load(GENESIS)).toBe("newer");
    store.close();
  });

  test("the genesis hash is normalised, so case cannot split a chain's blob", async () => {
    const store = openIndexedDbWarmStore();
    await store.save(GENESIS.toUpperCase().replace("0X", "0x"), "state");
    expect(await store.load(GENESIS)).toBe("state");
    store.close();
  });

  test("a malformed genesis hash is rejected rather than stored under it", async () => {
    const store = openIndexedDbWarmStore();
    await expect(store.load("0xabc")).rejects.toBeInstanceOf(WarmStoreError);
    await expect(store.save("not-a-hash", "state")).rejects.toBeInstanceOf(
      WarmStoreError,
    );
    store.close();
  });

  test("separate database names do not see each other's blobs", async () => {
    const mine = openIndexedDbWarmStore({ databaseName: "warm-a" });
    const theirs = openIndexedDbWarmStore({ databaseName: "warm-b" });
    await mine.save(GENESIS, "state");
    expect(await theirs.load(GENESIS)).toBeNull();
    mine.close();
    theirs.close();
  });

  test("a store reopens itself after close, so a closed store is reusable", async () => {
    const store = openIndexedDbWarmStore();
    await store.save(GENESIS, "state");
    store.close();
    expect(await store.load(GENESIS)).toBe("state");
    store.close();
  });

  // The provider reads an empty result as "nothing stored yet" and lets the
  // next persist overwrite, so an unavailable store must never look empty.
  test("no IndexedDB rejects rather than reading as absent", async () => {
    delete (globalThis as { indexedDB?: IDBFactory }).indexedDB;
    const store = openIndexedDbWarmStore();
    await expect(store.load(GENESIS)).rejects.toBeInstanceOf(WarmStoreError);
    await expect(store.save(GENESIS, "state")).rejects.toBeInstanceOf(
      WarmStoreError,
    );
  });

  test("a non-string stored value is reported instead of handed to the client", async () => {
    const store = openIndexedDbWarmStore({ databaseName: "warm-corrupt" });
    await store.save(GENESIS, "state");
    store.close();

    await new Promise<void>((resolve, reject) => {
      const request = globalThis.indexedDB.open("warm-corrupt", 1);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const tx = db.transaction("chain-databases", "readwrite");
        tx.objectStore("chain-databases").put(42, GENESIS);
        tx.oncomplete = () => {
          db.close();
          resolve();
        };
        tx.onerror = () => reject(tx.error);
      };
    });

    const reopened = openIndexedDbWarmStore({ databaseName: "warm-corrupt" });
    await expect(reopened.load(GENESIS)).rejects.toBeInstanceOf(WarmStoreError);
    reopened.close();
  });

  test("the default database name is the documented one", () => {
    expect(DEFAULT_WARM_STORE_DATABASE_NAME).toBe("truapi-provider-warm-start");
  });
});

describe("startWarmStartPersistence", () => {
  const settle = (ms = 12) => new Promise((r) => setTimeout(r, ms));

  test("waits for the initial delay, then persists every chain each round", async () => {
    const calls: string[] = [];
    const stop = startWarmStartPersistence(
      {
        persist: async (genesis) => {
          calls.push(genesis);
          return true;
        },
      },
      [GENESIS, OTHER_GENESIS],
      { initialDelayMs: 5, intervalMs: 10 },
    );

    expect(calls).toEqual([]);
    await settle(8);
    expect(calls).toEqual([GENESIS, OTHER_GENESIS]);
    await settle(12);
    expect(calls.length).toBe(4);
    stop();
  });

  test("stop() ends the loop", async () => {
    let count = 0;
    const stop = startWarmStartPersistence(
      {
        persist: async () => {
          count += 1;
          return true;
        },
      },
      [GENESIS],
      { initialDelayMs: 5, intervalMs: 5 },
    );
    await settle(8);
    const afterFirst = count;
    stop();
    await settle(20);
    expect(count).toBe(afterFirst);
  });

  test("stop() before the first round persists nothing at all", async () => {
    let count = 0;
    const stop = startWarmStartPersistence(
      {
        persist: async () => {
          count += 1;
          return true;
        },
      },
      [GENESIS],
      { initialDelayMs: 20, intervalMs: 20 },
    );
    stop();
    await settle(35);
    expect(count).toBe(0);
  });

  // A slow chain must not build a backlog of snapshots of the same state.
  test("a round still running skips the next tick instead of overlapping", async () => {
    let active = 0;
    let overlapped = false;
    const stop = startWarmStartPersistence(
      {
        persist: async () => {
          active += 1;
          if (active > 1) overlapped = true;
          await new Promise((r) => setTimeout(r, 20));
          active -= 1;
          return true;
        },
      },
      [GENESIS],
      { initialDelayMs: 2, intervalMs: 3 },
    );
    await settle(40);
    stop();
    expect(overlapped).toBe(false);
  });

  test("one chain's failure is reported and does not stop the others", async () => {
    const seen: string[] = [];
    const errors: string[] = [];
    const stop = startWarmStartPersistence(
      {
        persist: async (genesis) => {
          seen.push(genesis);
          if (genesis === GENESIS) throw new Error("store is full");
          return true;
        },
      },
      [GENESIS, OTHER_GENESIS],
      {
        initialDelayMs: 3,
        intervalMs: 50,
        onError: (_error, genesis) => errors.push(genesis),
      },
    );
    await settle(15);
    stop();
    expect(seen).toEqual([GENESIS, OTHER_GENESIS]);
    expect(errors).toEqual([GENESIS]);
  });
});
