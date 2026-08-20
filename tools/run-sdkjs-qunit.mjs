#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL, fileURLToPath } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.dirname(toolsDir);
const agentDir = path.join(
  rootDir,
  "desktop-sdk/ChromiumBasedEditors/plugins/ai-agent"
);
const require = createRequire(import.meta.url);
const { chromium } = require(path.join(agentDir, "node_modules/playwright"));

const defaultPages = [
  "word/plugins/pluginsApi.html",
  "word/plugins/multimodalSnapshot.html",
  "word/plugins/documentWordEditPlan.html",
  "word/plugins/remoteCollaborativeApply.html",
  "word/plugins/selectionParagraphFormatting.html",
  "word/plugins/selectionListFormatting.html",
  "word/plugins/selectionComment.html",
  "word/plugins/selectionTableCellText.html",
  "word/plugins/documentBodyText.html",
  "word/plugins/documentTextReplacement.html",
];
const requestedPages = process.argv.slice(2);
const pages = requestedPages.length > 0 ? requestedPages : defaultPages;

function resolveExecutable() {
  if (process.env.PLAYWRIGHT_CHROME_EXECUTABLE) {
    return process.env.PLAYWRIGHT_CHROME_EXECUTABLE;
  }
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  ];
  return candidates.find((candidate) => fs.existsSync(candidate));
}

async function runPage(browser, relativePage) {
  if (path.isAbsolute(relativePage) || relativePage.includes("..")) {
    throw new Error(`SDKJS test path must be relative to sdkjs/tests: ${relativePage}`);
  }
  const filePath = path.join(rootDir, "sdkjs/tests", relativePage);
  if (!fs.existsSync(filePath)) throw new Error(`SDKJS test page is missing: ${relativePage}`);

  const page = await browser.newPage();
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  try {
    await page.goto(pathToFileURL(filePath).href, {
      waitUntil: "load",
      timeout: 120_000,
    });
    await page.waitForFunction(
      () => {
        const banner = document.querySelector("#qunit-banner");
        return (
          banner?.classList.contains("qunit-pass") ||
          banner?.classList.contains("qunit-fail")
        );
      },
      undefined,
      { timeout: 120_000 }
    );
    const result = await page.evaluate(() => ({
      banner: document.querySelector("#qunit-banner")?.className ?? "",
      tests: document.querySelectorAll("#qunit-tests > li").length,
      failedTests: document.querySelectorAll("#qunit-tests > li.fail").length,
      assertions: window.QUnit?.config?.stats?.all ?? 0,
      failedAssertions: window.QUnit?.config?.stats?.bad ?? 0,
    }));
    if (
      result.banner !== "qunit-pass" ||
      result.tests === 0 ||
      result.failedTests !== 0 ||
      result.failedAssertions !== 0 ||
      pageErrors.length > 0
    ) {
      throw new Error(
        `${relativePage} failed: ${JSON.stringify({ ...result, pageErrors })}`
      );
    }
    console.log(
      `OK SDKJS QUnit: ${relativePage} (${result.tests} tests, ${result.assertions} assertions)`
    );
  } finally {
    await page.close();
  }
}

let browser;
try {
  const executablePath = resolveExecutable();
  browser = await chromium.launch({
    headless: true,
    ...(executablePath ? { executablePath } : {}),
    args: ["--allow-file-access-from-files"],
  });
  for (const page of pages) await runPage(browser, page);
} catch (error) {
  console.error(`SDKJS QUnit verification failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await browser?.close();
}
