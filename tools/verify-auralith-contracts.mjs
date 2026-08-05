#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const toolsDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.dirname(toolsDir);
const require = createRequire(import.meta.url);

const paths = Object.freeze({
  registry: path.join(
    rootDir,
    "desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/src/office-tools/office-capabilities.json"
  ),
  buildScript: path.join(
    rootDir,
    "desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/scripts/build.js"
  ),
  host: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-host.js"
  ),
  hostRuntime: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-host-runtime.js"
  ),
  hostStyle: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-host.css"
  ),
  executor: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-write-executor.js"
  ),
  writeProfiles: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-write-profiles.js"
  ),
  transport: path.join(
    rootDir,
    "web-apps/apps/common/main/lib/auralith-agent-write-transport.js"
  ),
  editorIndexes: Object.freeze({
    document: path.join(rootDir, "web-apps/apps/documenteditor/main/index.html"),
    spreadsheet: path.join(rootDir, "web-apps/apps/spreadsheeteditor/main/index.html"),
    presentation: path.join(rootDir, "web-apps/apps/presentationeditor/main/index.html"),
    pdf: path.join(rootDir, "web-apps/apps/pdfeditor/main/index.html"),
    visio: path.join(rootDir, "web-apps/apps/visioeditor/main/index.html"),
  }),
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

async function main() {
  const registry = readJson(paths.registry);
  const host = readText(paths.host);
  const hostRuntime = readText(paths.hostRuntime);
  const hostStyle = readText(paths.hostStyle);
  const writeProfiles = readText(paths.writeProfiles);
  const writeProfileContract = require(paths.writeProfiles);
  const executor = readText(paths.executor);
  const transport = readText(paths.transport);
  const editorIndexes = Object.fromEntries(
    Object.entries(paths.editorIndexes).map(([kind, filePath]) => [
      kind,
      readText(filePath),
    ])
  );
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
  // deploy/auralith-agent is ignored and may legitimately contain an older
  // local install. Verify the canonical manifest generator itself here; the
  // isolated build/install stages verify their freshly generated artifact.
  const buildModule = await import(
    `${pathToFileURL(paths.buildScript).href}?verify=${Date.now()}`
  );
  assert.deepEqual(
    buildModule.createBuiltInAgentManifest(
      buildModule.loadOfficeCapabilityRegistry()
    ),
    expectedManifest
  );

  assert.equal(parseStringConst(host, "OFFICE_PROTOCOL_VERSION"), registry.protocolVersion);
  assert.equal(
    parseStringConst(host, "HOST_RUNTIME_CONTRACT_VERSION"),
    parseStringConst(hostRuntime, "CONTRACT_VERSION"),
    "Host and pure runtime contract versions disagree."
  );
  assert.match(hostRuntime, /return Object\.freeze\(\{/u);
  assert.doesNotMatch(hostRuntime, /addEventListener\s*\(\s*["']message["']/u);
  assert.doesNotMatch(hostRuntime, /\bpostMessage\b/u);
  assert.equal(parseStringConst(writeProfiles, "CONTRACT_VERSION"), "1.0");
  assert.equal(writeProfileContract.contractVersion, "1.0");
  assert.ok(Object.isFrozen(writeProfileContract));
  assert.ok(Object.isFrozen(writeProfileContract.profiles));
  assert.match(writeProfiles, /return Object\.freeze\(\{/u);
  assert.doesNotMatch(writeProfiles, /\bregister[A-Za-z]*\s*[:=]/u);
  assert.match(executor, /writeProfiles\.getProfile\s*\(/u);
  assert.equal(
    hostStyle.replace(/^\uFEFF/u, "").replace(/\r\n?/gu, "\n"),
    '/* Stable cascade entrypoint for the Auralith Agent Host UI. */\n' +
      '@import url("./auralith-agent-host-tokens.css");\n' +
      '@import url("./auralith-agent-host-base-layout.css");\n' +
      '@import url("./auralith-agent-host-write-approval.css");\n'
  );
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
  for (const profile of writeProfileContract.profiles) {
    assert.ok(Object.isFrozen(profile), `Write profile ${profile.key} is mutable.`);
    const capability = registry.capabilities.find(
      (candidate) => candidate.id === profile.capabilityId
    );
    assert.ok(capability, `${profile.capabilityId} is missing from the canonical registry.`);
    assert.equal(capability.version, profile.capabilityVersion);
    assert.equal(capability.productionEnabled, true);
    const inspect = capability.operations.find((candidate) => candidate.id === "inspect");
    const apply = capability.operations.find((candidate) => candidate.id === profile.operation);
    assert.ok(inspect, `${profile.capabilityId}/inspect is missing.`);
    assert.ok(apply, `${profile.capabilityId}/${profile.operation} is missing.`);
    assert.equal(inspect.transport.method, profile.inspectSdkMethod);
    assert.equal(apply.transport.method, profile.applySdkMethod);
    assert.equal(apply.effect, "write");
    assert.equal(apply.approval, "required");
    for (const sdkMethod of [profile.inspectSdkMethod, profile.applySdkMethod]) {
      assert.ok(
        writeProfiles.includes(JSON.stringify(sdkMethod)),
        `Closed Host write profiles omit ${sdkMethod}.`
      );
      assert.ok(
        !executor.includes(sdkMethod),
        `The generic executor hard-codes SDK method ${sdkMethod}.`
      );
    }
  }

  const documentEditorIndex = editorIndexes.document;
  const runtimeIndex = documentEditorIndex.indexOf("auralith-agent-host-runtime.js");
  const profilesIndex = documentEditorIndex.indexOf("auralith-agent-write-profiles.js");
  const executorIndex = documentEditorIndex.indexOf("auralith-agent-write-executor.js");
  const transportIndex = documentEditorIndex.indexOf("auralith-agent-write-transport.js");
  const hostIndex = documentEditorIndex.indexOf("auralith-agent-host.js");
  assert.ok(runtimeIndex >= 0, "Document Editor does not load the Host runtime.");
  assert.ok(profilesIndex >= 0, "Document Editor does not load the closed write profiles.");
  assert.ok(executorIndex >= 0, "Document Editor does not load the write executor.");
  assert.ok(
    runtimeIndex > profilesIndex && executorIndex > runtimeIndex && transportIndex > executorIndex,
    "Document Editor must load profiles, runtime, executor, then write transport."
  );
  assert.ok(
    hostIndex > transportIndex,
    "Document Editor must load the write transport before the Host."
  );
  for (const [kind, source] of Object.entries(editorIndexes)) {
    const sharedRuntimeIndex = source.indexOf("auralith-agent-host-runtime.js");
    const sharedHostIndex = source.indexOf("auralith-agent-host.js");
    assert.ok(
      sharedRuntimeIndex >= 0 && sharedHostIndex > sharedRuntimeIndex,
      `${kind} editor must load the runtime before the Host.`
    );
    if (kind !== "document") {
      assert.ok(
        !source.includes("auralith-agent-write-profiles.js") &&
          !source.includes("auralith-agent-write-executor.js") &&
          !source.includes("auralith-agent-write-transport.js"),
        `${kind} editor must not load the DOCX write path.`
      );
    }
  }

  for (const source of [
    "word/Editor/document/content-change-feed.js",
    "word/Editor/document/multimodal-snapshot.js",
    "word/Editor/document/selection-text-formatting.js",
    "word/Editor/document/selection-paragraph-formatting.js",
    "word/Editor/document/selection-comment.js",
    "word/Editor/document/selection-list-formatting.js",
    "word/Editor/document/selection-table-cell-text.js",
  ]) {
    assert.ok(wordConfig.includes(`\"${source}\"`), `Word build config omits ${source}.`);
  }
  for (const page of [
    "word/plugins/pluginsApi.html",
    "word/plugins/multimodalSnapshot.html",
    "word/plugins/selectionParagraphFormatting.html",
    "word/plugins/selectionComment.html",
    "word/plugins/selectionListFormatting.html",
    "word/plugins/selectionTableCellText.html",
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
  await main();
} catch (error) {
  console.error(`Contract verification failed: ${error.message}`);
  process.exitCode = 1;
}
