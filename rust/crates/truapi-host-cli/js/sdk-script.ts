#!/usr/bin/env bun

import {
  bindHost,
  getHostLocalStorage,
  type TruApi,
} from "@parity/product-sdk/host";
import type { HostContext, ScriptAssert } from "./script.types.d.ts";

declare const truapi: TruApi;
declare const host: HostContext;
declare const assert: ScriptAssert;

bindHost({
  client: truapi,
  signal: host.signal,
  apiVersion: host.apiVersion,
});

const storage = await getHostLocalStorage();
assert(storage, "Host storage API unavailable");
console.log("product", host.productId);
console.log("saved value", await storage.readString("example"));
