import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer, request as httpRequest } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

let directory, app, origin, client;
let logs = "";
before(async () => {
  directory = await mkdtemp(join(tmpdir(), "rebstock-local-mcp-"));
  const reservation = createServer();
  reservation.listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  origin = `http://127.0.0.1:${port}`;
  const config = join(directory, "config.json");
  await writeFile(config, JSON.stringify({
    host: "127.0.0.1", port,
    database_uri: `file:${join(directory, "test.db")}`,
    image_dir: join(directory, "images"),
    auth: { single: { user: "local-dev" } },
  }));
  app = spawn("gleam", ["run", "-m", "rebstock_dev", "--", "--config", config], {
    detached: true, stdio: ["ignore", "pipe", "pipe"],
  });
  app.stdout.on("data", data => { logs += data; });
  app.stderr.on("data", data => { logs += data; });
  let ready = false;
  for (let i = 0; i < 150; i++) {
    if (app.exitCode !== null) throw new Error(logs);
    try { ready = (await fetch(`${origin}/mcp`)).status === 405; } catch {}
    if (ready) break;
    await delay(100);
  }
  assert.ok(ready, logs);
  client = new Client({ name: "local-dev-test", version: "1" });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${origin}/mcp`), {
    requestInit: { headers: { "x-webauth-user": "intruder", "authorization": "Bearer not-a-token" } },
  }));
});
after(async () => {
  await client?.close();
  if (app?.pid && app.exitCode === null && app.signalCode === null) {
    const exited = once(app, "exit");
    process.kill(-app.pid, "SIGTERM");
    const force = setTimeout(() => { try { process.kill(-app.pid, "SIGKILL"); } catch {} }, 3000);
    force.unref();
    await exited;
    clearTimeout(force);
  }
  if (directory) await rm(directory, { recursive: true, force: true });
});
async function tool(name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  assert.ok(!result.isError, JSON.stringify(result));
  return result.structuredContent;
}

test("official SDK connects without OAuth and imports under the configured single user", async () => {
  assert.equal((await client.listTools()).tools.length, 8);
  const baseline = (await tool("get_cellar", { limit: 100 })).entries;
  const batch = {
    source: "test:local-dev-seed-v1",
    wines: [{ ref: "wine", winery: "Local MCP Test Estate", name: "Seed Riesling", country: "DE", wine_type: "WHITE", vintages: [{ year: "2023" }] }],
    cellar: [{ ref: "purchase", wine_ref: "wine", vintage: "2023", quantity: 3, price_cents: 1250, date: "2026-11-08", notes: "Local MCP seed test" }],
  };
  const preview = await tool("import_batch", batch);
  assert.equal(preview.apply, false);
  assert.equal(preview.counts.bottles, 3);
  assert.deepEqual((await tool("get_cellar", { limit: 100 })).entries, baseline);
  const applied = await tool("import_batch", { ...batch, apply: true });
  assert.equal(applied.counts.created, 2);
  const replay = await tool("import_batch", { ...batch, apply: true });
  assert.equal(replay.counts.created, 0);
  assert.equal(replay.counts.bottles, 0);
  assert.deepEqual(replay.records.map(r => r.id), applied.records.map(r => r.id));
  const wineId = applied.records.find(r => r.kind === "wines").id;
  const entries = (await tool("get_cellar", { wine_id: wineId })).entries;
  assert.equal(entries.length, 1);
  assert.equal(entries[0].quantity, 3);
  assert.equal(entries[0].price_cents, 1250);
  assert.ok((await (await fetch(`${origin}/~local-dev/cellar/export.csv`)).text()).includes("Seed Riesling"));
  assert.equal((await fetch(`${origin}/~intruder/cellar/export.csv`)).status, 403);
});

test("local MCP rejects browser cross-origin requests and DNS rebinding hosts", async () => {
  for (const headers of [
    { origin: "https://evil.example" },
    { origin: "null" },
    { host: "evil.example" },
    { host: "localhost:1" },
    { "sec-fetch-site": "cross-site" },
  ]) {
    // fetch may discard a custom Host header; use HTTP directly for rebinding checks.
    const status = await new Promise((resolve, reject) => {
      const req = httpRequest(`${origin}/mcp`, { method: "POST", headers }, response => {
        response.resume();
        response.on("end", () => resolve(response.statusCode));
      });
      req.on("error", reject);
      req.end();
    });
    assert.equal(status, 403, JSON.stringify(headers));
  }
  assert.equal((await fetch(`${origin}/mcp`, { method: "OPTIONS", headers: { origin: "https://evil.example" } })).status, 403);
  assert.equal((await fetch(`${origin}/.well-known/oauth-protected-resource`)).status, 404);
  const response = await fetch(`${origin}/mcp`, {
    method: "POST", headers: { origin, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }),
  });
  assert.equal(response.status, 200);
});
