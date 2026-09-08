import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { IDBFactory } from "fake-indexeddb";

import {
  DEFAULT_WARM_STORE_DATABASE_NAME,
  WarmStoreError,
  openIndexedDbWarmStore,
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
