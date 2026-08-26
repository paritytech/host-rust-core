/**
 * Full TrUAPI diagnosis against a local `truapi-host dev`.
 *
 * The product runs in a plain browser tab, hosted through the bridge script the
 * CLI serves, so there is no host shell to sign into and no confirmation modal
 * to click: `dev` auto-approves. What is left is the playground's own coverage
 * report, written next to the committed ones for comparison.
 */
import { chromium, type Browser, type Page } from "playwright-core";
import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createConnection } from "node:net";

const currentDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(currentDir, "../../..");
const playgroundRoot = resolve(repoRoot, "playground");
const outputDir = resolve(playgroundRoot, "test-results/e2e-cli");

const appPort = Number(process.env.E2E_CLI_APP_PORT ?? 3000);
const hostPort = Number(process.env.E2E_CLI_HOST_PORT ?? 9955);
const network = process.env.E2E_CLI_NETWORK ?? "paseo-next-v2";
const devCommand = process.env.E2E_CLI_DEV_COMMAND ?? "yarn dev";
const hostBinary =
  process.env.TRUAPI_HOST_BIN ?? resolve(repoRoot, "target/release/truapi-host");
const browserChannel = process.env.PLAYWRIGHT_CHANNEL;
const headless = process.env.HEADED !== "1";
const diagnosisTimeoutMs = Number(
  process.env.E2E_CLI_DIAGNOSIS_TIMEOUT_MS ?? 20 * 60_000,
);

function log(message: string): void {
  console.log(`[e2e-cli] ${message}`);
}

function sleep(ms: number): Promise<void> {
  return new Promise((done) => setTimeout(done, ms));
}

function portIsOpen(port: number): Promise<boolean> {
  return new Promise((done) => {
    const socket = createConnection({ port, host: "127.0.0.1" });
    socket.once("connect", () => (socket.destroy(), done(true)));
    socket.once("error", () => (socket.destroy(), done(false)));
  });
}

async function waitForPort(port: number, label: string): Promise<void> {
  const deadline = Date.now() + 5 * 60_000;
  while (Date.now() < deadline) {
    if (await portIsOpen(port)) return;
    await sleep(2_000);
  }
  throw new Error(`${label} did not come up on :${port}`);
}

/** Start `truapi-host dev`, or adopt a stack already serving the app port. */
async function startStack(): Promise<ChildProcess | null> {
  if (await portIsOpen(appPort)) {
    log(`reusing the stack already serving :${appPort}`);
    return null;
  }
  log(`starting ${hostBinary} dev -- ${devCommand}`);
  const child = spawn(
    hostBinary,
    ["dev", "--app-port", String(appPort), "--port", String(hostPort),
     "--network", network, "--", ...devCommand.split(" ")],
    // Detached, so the host leads its own process group and stopping it takes
    // the dev server with it rather than this runner.
    { cwd: playgroundRoot, stdio: ["ignore", "pipe", "pipe"], detached: true },
  );
  const relay = (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (line.trim()) console.log(`[host] ${line}`);
    }
  };
  child.stdout?.on("data", relay);
  child.stderr?.on("data", relay);
  await waitForPort(appPort, "playground");
  return child;
}

/** Run the diagnosis and return the report the playground itself renders. */
async function runDiagnosis(page: Page): Promise<{
  summary: string;
  report: string;
  failed: string[];
  skipped: string[];
}> {
  await page.locator('[data-testid="diagnosis-run"]').click();
  log("diagnosis running");

  const deadline = Date.now() + diagnosisTimeoutMs;
  let lastLogAt = 0;
  while (Date.now() < deadline) {
    const ready = await page
      .locator('[data-testid="diagnosis-copy-report"]')
      .isVisible({ timeout: 1_000 })
      .catch(() => false);
    if (ready) break;
    if (Date.now() - lastLogAt >= 30_000) {
      lastLogAt = Date.now();
      log(`progress: ${await progressLine(page)}`);
    }
    await sleep(5_000);
  }
  if (!(await page.locator('[data-testid="diagnosis-copy-report"]').isVisible())) {
    throw new Error(`diagnosis did not finish within ${diagnosisTimeoutMs}ms`);
  }

  const summary = await page
    .locator('[data-testid="diagnosis-summary"]')
    .innerText({ timeout: 5_000 });
  const report =
    (await page
      .locator('[data-testid="diagnosis-report-markdown"]')
      .textContent({ timeout: 5_000 })) ?? "";
  if (report.trim().length === 0) {
    throw new Error("diagnosis report markdown is empty");
  }
  // Skipped methods render as failures but are intentional gaps, so they are
  // reported separately from the ones that actually broke.
  const failed = await page
    .locator(
      '[data-testid="diagnosis-row"][data-status="fail"]:not([data-skipped="true"]) .diag__name',
    )
    .allInnerTexts();
  const skipped = await page
    .locator('[data-testid="diagnosis-row"][data-skipped="true"] .diag__name')
    .allInnerTexts();
  return { summary, report, failed, skipped };
}

async function progressLine(page: Page): Promise<string> {
  return page.evaluate(() => {
    const counts: Record<string, number> = {};
    let running = "none";
    for (const row of document.querySelectorAll<HTMLElement>(
      '[data-testid="diagnosis-row"]',
    )) {
      const status = row.dataset.status ?? "unknown";
      counts[status] = (counts[status] ?? 0) + 1;
      if (status === "running") {
        running =
          row.querySelector<HTMLElement>(".diag__name")?.innerText ?? "unknown";
      }
    }
    return `${Object.entries(counts)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([status, count]) => `${status}=${count}`)
      .join(" ")} running=${running}`;
  });
}

async function main(): Promise<void> {
  mkdirSync(outputDir, { recursive: true });
  const stack = await startStack();
  const pageErrors: string[] = [];
  let browser: Browser | undefined;

  try {
    browser = await chromium.launch({
      headless,
      ...(browserChannel ? { channel: browserChannel } : {}),
    });
    const page = await browser.newPage();
    // Unlike @playwright/test, playwright-core defaults to no action timeout,
    // so an element that never becomes actionable would hang the run.
    page.setDefaultTimeout(60_000);
    page.on("pageerror", (error) => pageErrors.push(String(error)));

    await page.addInitScript(() => {
      localStorage.setItem("truapi:playground:e2e", "1");
      (
        window as typeof window & { __TRUAPI_PLAYGROUND_E2E__?: boolean }
      ).__TRUAPI_PLAYGROUND_E2E__ = true;
    });
    // The diagnosis screen is deep-linked by `?view=`, which the playground
    // supports so the screen can be reached without driving the service rail.
    await page.goto(`http://localhost:${appPort}/?view=diagnosis`, {
      waitUntil: "domcontentloaded",
      timeout: 60_000,
    });
    await page
      .locator('[data-testid="diagnosis-run"]')
      .waitFor({ state: "visible", timeout: 60_000 });
    log("playground is hosted; starting diagnosis");

    const { summary, report, failed, skipped } = await runDiagnosis(page);
    const reportPath = resolve(outputDir, "diagnosis-report.md");
    writeFileSync(reportPath, `${report.trim()}\n`);
    writeFileSync(
      resolve(outputDir, "diagnosis-run.json"),
      `${JSON.stringify(
        {
          host: "truapi-host dev",
          network,
          summary,
          failed,
          skipped,
          pageErrors,
          timestamp: new Date().toISOString(),
        },
        null,
        2,
      )}\n`,
    );

    log(`summary: ${summary.replace(/\s+/g, " ").trim()}`);
    log(`report: ${reportPath}`);
    if (skipped.length > 0) log(`skipped (${skipped.length}): ${skipped.join(", ")}`);
    if (pageErrors.length > 0) {
      throw new Error(`browser page errors occurred: ${pageErrors.length}`);
    }
    if (failed.length > 0) {
      throw new Error(`diagnosis failures: ${failed.join(", ")}`);
    }
    log("diagnosis complete with no unexpected failures");
  } finally {
    await browser?.close();
    if (stack?.pid) {
      try {
        process.kill(-stack.pid, "SIGTERM");
      } catch {
        stack.kill("SIGTERM");
      }
      await sleep(3_000);
    }
  }
}

main().catch((error) => {
  console.error(`[e2e-cli] ${error instanceof Error ? error.message : error}`);
  process.exit(1);
});
