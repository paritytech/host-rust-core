import { describe, expect, test } from "bun:test";
import {
  NETWORK_PRESETS,
  resolveNetwork,
  resolveProductId,
} from "./networks.js";

describe("resolveNetwork", () => {
  test("defaults to paseo-next-v2", () => {
    expect(resolveNetwork().name).toBe("paseo-next-v2");
  });

  test("resolves friendly aliases to CLI preset names", () => {
    expect(resolveNetwork("nextv2").name).toBe("paseo-next-v2");
    expect(resolveNetwork("preview").name).toBe("previewnet");
  });

  test("accepts CLI-native names verbatim", () => {
    expect(resolveNetwork("previewnet").name).toBe("previewnet");
  });

  test("throws on unknown names instead of starting against the wrong network", () => {
    expect(() => resolveNetwork("mainnet")).toThrow(/unknown TrUAPI network/);
  });
});

describe("resolveProductId", () => {
  const nextv2 = NETWORK_PRESETS["paseo-next-v2"];
  const preview = NETWORK_PRESETS["previewnet"];

  test("falls back to the app-derived id without an override", () => {
    expect(resolveProductId(undefined, nextv2, "localhost:3000")).toBe(
      "localhost:3000",
    );
  });

  test("resolves a bare label into the network's namespace", () => {
    expect(resolveProductId("play", nextv2, "localhost:3000")).toBe(
      "play.paseo",
    );
    expect(resolveProductId("play", preview, "localhost:3000")).toBe(
      "play.dot",
    );
  });

  test("respects qualified ids and localhost ids verbatim", () => {
    expect(resolveProductId("dim2.paseo", nextv2, "localhost:3000")).toBe(
      "dim2.paseo",
    );
    expect(resolveProductId("localhost:3001", nextv2, "localhost:3000")).toBe(
      "localhost:3001",
    );
  });
});
