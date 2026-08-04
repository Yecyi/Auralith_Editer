#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.dirname(toolsDir);

const paths = Object.freeze({
  registry: path.join(
    rootDir,
    "desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/src/office-tools/office-capabilities.json"
  ),
  manifest: path.join(
    rootDir,
    "desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/deploy/auralith-agent/manifest.json"
  ),
  host: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-host.js"
  ),
  executor: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-write-executor.js"
  ),
  transport: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-write-transport.js"
  ),
  documentEditorIndex: path.join(
    rootDir,
    "web-apps/apps/documenteditor/main/index.html"
  ),
  wordConfig: path.join(rootDir, "sdkjs/configs/word.json"),
  sdkRunAll: path.join(rootDir, "sdkjs/tests/runAll.js"),
});

function readText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (error) {
    throw new Error(`Cannot read ${path.relative(rootDir, filePath)}: ${error.message}`);
  }
}

function readJson(filePath) {
  try {
    return JSON.parse(readText(filePath));
  } catch (error) {
    throw new Error(`Invalid JSON in ${path.relative(rootDir, filePath)}: ${error.message}`);
  }
}

function matchConst(source, name, valuePattern) {
  const match = source.match(
    new RegExp(`\\bvar\\s+${name}\\s*=\\s*(${valuePattern})\\s*;`)
  );
  assert.ok(match, `Host/executor constant ${name} is missing or malformed.`);
  return match[1];
}

function parseStringConst(source, name) {
  return JSON.parse(matchConst(source, name, '"[^"\\n]*"'));
}

function parseBooleanConst(source, name) {
  return matchConst(source, name, "true|false") === "true";
}

function parseHostAllowlist(source) {
  const match = source.match(/var ALLOWED_METHODS = \{([\s\S]*?)\n\s*\};/u);
  assert.ok(match, "Host ALLOWED_METHODS must remain an explicit object literal.");
  const methods = [];
  const entryPattern = /^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*true\s*,?\s*$/gmu;
  for (const entry of match[1].matchAll(entryPattern)) methods.push(entry[1]);
  const residue = match[1]
    .replace(entryPattern, "")
    .replace(/\/\/[^\n]*/gu, "")
    .trim();
  assert.equal(residue, "", "Host ALLOWED_METHODS contains a non-canonical entry.");
  return methods;
}

function projectCapability(capability) {
  return {
    id: capability.id,
    version: capability.version,
    status: capability.status,
    productionEnabled: capability.productionEnabled,
    ...(typeof capability.blockedReason === "string"
      ? { blockedReason: capability.blockedReason }
      : {}),
    operations: capability.operations.map((operation) => ({
      id: operation.id,
      effect: operation.effect,
      approval: operation.approval,
      undo: operation.undo,
      transportMethod: operation.transport?.method,
      builtinRpc: operation.transport?.builtinRpc === true,
    })),
  };
}

function verifyRegistry(registry) {
  assert.equal(typeof registry.registryVersion, "string");
  assert.equal(typeof registry.protocolVersion, "string");
  assert.ok(Array.isArray(registry.capabilities) && registry.capabilities.length > 0);

  const capabilityIds = new Set();
  const transportMethods = new Set();
  for (const capability of registry.capabilities) {
    assert.equal(typeof capability.id, "string");
    assert.ok(!capabilityIds.has(capability.id), `Duplicate capability: ${capability.id}`);
    capabilityIds.add(capability.id);
    assert.equal(
      capability.productionEnabled,
      capability.status === "enabled",
      `${capability.id} status and productionEnabled disagree.`
    );
    if (capability.productionEnabled) {
      assert.ok(!capability.blockedReason, `${capability.id} is enabled but has a blockedReason.`);
    } else {
      assert.equal(capability.status, "blocked");
      assert.equal(typeof capability.blockedReason, "string");
      assert.ok(capability.blockedReason.length > 0);
    }
    assert.ok(Array.isArray(capability.operations) && capability.operations.length > 0);
    const operationIds = new Set();
    for (const operation of capability.operations) {
      assert.ok(!operationIds.has(operation.id), `Duplicate operation: ${capability.id}/${operation.id}`);
      operationIds.add(operation.id);
      const method = operation.transport?.method;
      assert.equal(typeof method, "string");
      assert.ok(!transportMethods.has(method), `Duplicate Office transport method: ${method}`);
      transportMethods.add(method);
      if (operation.transport.builtinRpc) {
        assert.equal(operation.effect, "read", `${method} exposes a write on built-in RPC.`);
        assert.equal(capability.productionEnabled, true, `${method} belongs to a blocked capability.`);
      }
    }
  }
}

function main() {
  const registry = readJson(paths.registry);
  const host = readText(paths.host);
  const executor = readText(paths.executor);
  const transport = readText(paths.transport);
  const documentEditorIndex = readText(paths.documentEditorIndex);
  const wordConfig = readText(paths.wordConfig);
  const sdkRunAll = readText(paths.sdkRunAll);

  verifyRegistry(registry);

  const expectedStatus = registry.capabilities.map(projectCapability);
  const expectedProductionCapabilities = expectedStatus
    .filter((capability) => capability.productionEnabled)
    .map((capability) => capability.id);
  const expectedManifest = {
    name: "Auralith Agent",
    kind: "builtin-editor-surface",
    entry: "reader.html",
    protocolVersion: registry.protocolVersion,
    capabilityRegistryVersion: registry.registryVersion,
    capabilities: expectedProductionCapabilities,
    capabilityStatus: expectedStatus,
  };
  // deploy/auralith-agent is generated and intentionally ignored. Verify it
  // when present, while keeping a fresh clone verifiable before the first
  // isolated Vite build.
  if (fs.existsSync(paths.manifest)) {
    assert.deepEqual(readJson(paths.manifest), expectedManifest);
  }

  assert.equal(parseStringConst(host, "OFFICE_PROTOCOL_VERSION"), registry.protocolVersion);
  const expectedBuiltinMethods = registry.capabilities.flatMap((capability) =>
    capability.operations
      .filter((operation) => operation.transport.builtinRpc)
      .map((operation) => operation.transport.method)
  );
  assert.deepEqual(parseHostAllowlist(host), expectedBuiltinMethods);

  const formatting = registry.capabilities.find(
    (capability) => capability.id === "document.selection-formatting"
  );
  assert.ok(formatting, "document.selection-formatting is missing.");
  assert.equal(
    parseBooleanConst(host, "WRITE_EXECUTOR_PRODUCTION_ENABLED"),
    formatting.productionEnabled,
    "Host write gate disagrees with the canonical selection-formatting capability."
  );
  assert.equal(parseStringConst(executor, "CAPABILITY_ID"), formatting.id);
  assert.equal(parseStringConst(executor, "CAPABILITY_VERSION"), formatting.version);
  assert.equal(
    parseStringConst(transport, "PROTOCOL_VERSION"),
    registry.protocolVersion,
    "Host write transport protocol disagrees with the capability registry."
  );
  assert.equal(
    parseStringConst(transport, "AUTHORIZE_TYPE"),
    "auralith-agent:tool-authorize"
  );
  assert.equal(
    parseStringConst(transport, "EXECUTE_TYPE"),
    "auralith-agent:tool-execute"
  );
  assert.equal(
    parseStringConst(transport, "CANCEL_TYPE"),
    "auralith-agent:tool-cancel"
  );
  assert.equal(
    parseStringConst(transport, "RESPONSE_TYPE"),
    "auralith-agent:tool-response"
  );
  for (const operationId of ["inspect", "apply"]) {
    const operation = formatting.operations.find((candidate) => candidate.id === operationId);
    assert.ok(operation, `selection-formatting/${operationId} is missing.`);
    const constantName = operationId === "inspect" ? "INSPECT_SDK_METHOD" : "APPLY_SDK_METHOD";
    assert.equal(parseStringConst(executor, constantName), operation.transport.method);
  }

  const executorIndex = documentEditorIndex.indexOf("auralith-agent-write-executor.js");
  const transportIndex = documentEditorIndex.indexOf("auralith-agent-write-transport.js");
  const hostIndex = documentEditorIndex.indexOf("auralith-agent-host.js");
  assert.ok(executorIndex >= 0, "Document Editor does not load the write executor.");
  assert.ok(
    transportIndex > executorIndex,
    "Document Editor must load the executor before the write transport."
  );
  assert.ok(
    hostIndex > transportIndex,
    "Document Editor must load the write transport before the Host."
  );

  for (const source of [
    "word/Editor/document/content-change-feed.js",
    "word/Editor/document/multimodal-snapshot.js",
    "word/Editor/document/selection-text-formatting.js",
  ]) {
    assert.ok(wordConfig.includes(`\"${source}\"`), `Word build config omits ${source}.`);
  }
  for (const page of [
    "word/plugins/pluginsApi.html",
    "word/plugins/multimodalSnapshot.html",
    "word/plugins/remoteCollaborativeApply.html",
  ]) {
    assert.ok(sdkRunAll.includes(`'${page}'`), `SDKJS default suite omits ${page}.`);
  }

  console.log(
    `OK contracts: ${registry.capabilities.length} capabilities, ` +
      `${expectedBuiltinMethods.length} built-in RPC methods, ` +
      `selection-formatting=${formatting.status}`
  );
}

try {
  main();
} catch (error) {
  console.error(`Contract verification failed: ${error.message}`);
  process.exitCode = 1;
}
