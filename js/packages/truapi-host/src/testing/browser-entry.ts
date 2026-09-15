// Entry point of the bundle the test host server serves.
//
// Reads what to run from the page URL rather than from a generated script, so
// the server can bundle once and serve every test: the fixture varies the
// query string, not the bundle.

import { startTestHost } from "./host-page.js";
import type { MockHostConfig } from "../web/create-mock-host.js";
import type { DevAccountName } from "./dev-accounts.js";

const params = new URLSearchParams(window.location.search);
const productUrl = params.get("product");
const rawMock = params.get("mock");

if (!productUrl) {
  throw new Error(
    "test host page needs a ?product= URL; the Playwright fixture sets it",
  );
}

const container = document.getElementById("product-container");
if (!container) {
  throw new Error("test host page is missing its #product-container element");
}

const accounts = params.get("accounts")?.split(",").filter(Boolean);
const login = params.get("login");
const productId = params.get("productId") ?? undefined;
const rawRuntimeConfig = params.get("runtimeConfig");

void startTestHost({
  productUrl,
  container,
  mock: rawMock ? (JSON.parse(rawMock) as MockHostConfig) : undefined,
  runtimeConfig: {
    ...(rawRuntimeConfig
      ? (JSON.parse(rawRuntimeConfig) as Record<string, unknown>)
      : {}),
    ...(productId ? { productId } : {}),
  },
  accounts: accounts as DevAccountName[] | undefined,
  loginBehavior: login === "manual" ? "manual" : "auto",
}).catch((error: unknown) => {
  // Surface boot failures in the page rather than only the console: a fixture
  // that times out waiting for the control surface should be able to read why.
  const message = error instanceof Error ? error.message : String(error);
  const banner = document.createElement("pre");
  banner.id = "test-host-error";
  banner.textContent = `test host failed to start: ${message}`;
  document.body.append(banner);
  throw error;
});
