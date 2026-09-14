// Entry point of the bundle the test host server serves.
//
// Reads what to run from the page URL rather than from a generated script, so
// the server can bundle once and serve every test: the fixture varies the
// query string, not the bundle.

import { startTestHost } from "./host-page.js";
import type { MockHostConfig } from "../web/create-mock-host.js";

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

void startTestHost({
  productUrl,
  container,
  mock: rawMock ? (JSON.parse(rawMock) as MockHostConfig) : undefined,
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
