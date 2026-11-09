import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { once } from "node:events";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { UnauthorizedError } from "@modelcontextprotocol/sdk/client/auth.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/sdk/types.js";
import { AjvJsonSchemaValidator } from "@modelcontextprotocol/sdk/validation/ajv";

const clientId = "rebstock-codex";
const scope = "rebstock:mcp";
const clients = new Set();
let fixture;

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}`;
}

async function closeServer(server) {
  if (!server?.listening) return;
  const closed = once(server, "close");
  server.close();
  server.closeAllConnections();
  await closed;
}

async function availablePort() {
  const reservation = createServer();
  await listen(reservation);
  const { port } = reservation.address();
  await closeServer(reservation);
  return port;
}

function json(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(body));
}

function jwt(username = "socket-alice", overrides = {}, privateKey = fixture.privateKey) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const header = encode({ alg: "RS256", typ: "at+jwt", kid: "socket-key" });
  const payload = encode({
    iss: fixture.issuer,
    aud: fixture.resource,
    client_id: clientId,
    scope,
    sub: username,
    preferred_username: username,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 300,
    ...overrides,
  });
  const signed = `${header}.${payload}`;
  return `${signed}.${sign("RSA-SHA256", Buffer.from(signed), privateKey).toString("base64url")}`;
}

async function stopApp(app) {
  if (!app?.pid) return;
  const running = app.exitCode === null && app.signalCode === null;
  const exited = running ? once(app, "exit") : undefined;
  const signal = (name) => {
    try {
      process.kill(-app.pid, name);
    } catch (error) {
      if (error.code !== "ESRCH") throw error;
    }
  };
  signal("SIGTERM");
  if (!running) return;
  const force = setTimeout(() => signal("SIGKILL"), 3000);
  force.unref();
  await exited;
  clearTimeout(force);
}

async function cleanup() {
  await Promise.allSettled([...clients].map((client) => client.close()));
  clients.clear();
  if (!fixture) return;
  await stopApp(fixture.app);
  await closeServer(fixture.authorizationServer);
  await closeServer(fixture.callbackServer);
  if (fixture.directory) await rm(fixture.directory, { recursive: true, force: true });
}

before(async () => {
  fixture = { authorizationRequests: [], tokenRequests: [], discoveryRequests: [], codes: new Map() };
  try {
    const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    fixture.privateKey = privateKey;
    fixture.jwk = { ...publicKey.export({ format: "jwk" }), kid: "socket-key", use: "sig", alg: "RS256" };
    fixture.callbackServer = createServer((request, response) => {
      const callback = new URL(request.url, fixture.callbackOrigin);
      fixture.callback = callback;
      response.end("Local OAuth callback received");
    });
    fixture.callbackOrigin = await listen(fixture.callbackServer);
    fixture.redirectUri = `${fixture.callbackOrigin}/callback`;
    fixture.authorizationServer = createServer(async (request, response) => {
      try {
        const url = new URL(request.url, fixture.issuer);
        if (url.pathname === "/jwks") return json(response, 200, { keys: [fixture.jwk] });
        if (url.pathname === "/.well-known/oauth-authorization-server") {
          fixture.discoveryRequests.push(url.pathname);
          return json(response, 200, {
            issuer: fixture.issuer,
            authorization_endpoint: `${fixture.issuer}/authorize`,
            token_endpoint: `${fixture.issuer}/token`,
            jwks_uri: `${fixture.issuer}/jwks`,
            response_types_supported: ["code"],
            grant_types_supported: ["authorization_code"],
            code_challenge_methods_supported: ["S256"],
            token_endpoint_auth_methods_supported: ["none"],
            scopes_supported: [scope],
          });
        }
        if (url.pathname === "/authorize") {
          const parameters = url.searchParams;
          assert.equal(parameters.get("client_id"), clientId);
          assert.equal(parameters.get("response_type"), "code");
          assert.equal(parameters.get("redirect_uri"), fixture.redirectUri);
          assert.equal(parameters.get("resource"), fixture.resource);
          assert.equal(parameters.get("scope"), scope);
          assert.equal(parameters.get("code_challenge_method"), "S256");
          assert.match(parameters.get("code_challenge"), /^[A-Za-z0-9_-]{43}$/);
          fixture.authorizationRequests.push(new URLSearchParams(parameters));
          const code = randomBytes(24).toString("base64url");
          fixture.codes.set(code, new URLSearchParams(parameters));
          const callback = new URL(fixture.redirectUri);
          callback.searchParams.set("code", code);
          callback.searchParams.set("state", parameters.get("state"));
          response.writeHead(302, { location: callback.href });
          return response.end();
        }
        if (url.pathname === "/token" && request.method === "POST") {
          const chunks = [];
          for await (const chunk of request) chunks.push(chunk);
          const parameters = new URLSearchParams(Buffer.concat(chunks).toString());
          const authorization = fixture.codes.get(parameters.get("code"));
          assert.ok(authorization, "The authorization code must be valid and single use");
          assert.equal(parameters.get("grant_type"), "authorization_code");
          assert.equal(parameters.get("client_id"), clientId);
          assert.equal(parameters.get("redirect_uri"), fixture.redirectUri);
          assert.equal(parameters.get("resource"), fixture.resource);
          assert.match(parameters.get("code_verifier"), /^[A-Za-z0-9._~-]{43,128}$/);
          assert.equal(
            createHash("sha256").update(parameters.get("code_verifier")).digest("base64url"),
            authorization.get("code_challenge"),
          );
          fixture.codes.delete(parameters.get("code"));
          fixture.tokenRequests.push({ clientId, resource: parameters.get("resource"), pkceVerified: true });
          return json(response, 200, { access_token: jwt("socket-oauth"), token_type: "Bearer", expires_in: 300, scope });
        }
        json(response, 404, { error: "not_found" });
      } catch (error) {
        fixture.issuerFailure = error;
        json(response, 400, { error: "invalid_request" });
      }
    });
    fixture.issuer = await listen(fixture.authorizationServer);
    const port = await availablePort();
    fixture.origin = `http://127.0.0.1:${port}`;
    fixture.resource = `${fixture.origin}/mcp`;
    fixture.directory = await mkdtemp(join(tmpdir(), "rebstock-mcp-"));
    await mkdir(join(fixture.directory, "images"));
    const config = join(fixture.directory, "config.json");
    await writeFile(config, JSON.stringify({
      host: "127.0.0.1",
      port,
      database_uri: `file:${join(fixture.directory, "test.db")}`,
      image_dir: join(fixture.directory, "images"),
      secret_key_base: "mcp-socket-test-secret-01234567890123456789",
      auth: { single: { user: "web-only-user" } },
      mcp: {
        resource: fixture.resource,
        issuer: fixture.issuer,
        jwks_uri: `${fixture.issuer}/jwks`,
        client_id: clientId,
        scope,
        username_claim: "preferred_username",
      },
    }));
    fixture.output = "";
    fixture.app = spawn("gleam", ["run", "--", "--config", config], {
      cwd: process.cwd(),
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    fixture.app.on("error", (error) => { fixture.appError = error; });
    for (const stream of [fixture.app.stdout, fixture.app.stderr]) {
      stream.on("data", (data) => { fixture.output = (fixture.output + data).slice(-8000); });
    }
    const deadline = Date.now() + 45_000;
    while (Date.now() < deadline) {
      if (fixture.appError) throw fixture.appError;
      assert.equal(fixture.app.exitCode, null, fixture.output);
      try {
        const response = await fetch(`${fixture.origin}/.well-known/oauth-protected-resource/mcp`, { signal: AbortSignal.timeout(500) });
        if (response.status === 200) return;
      } catch {}
      await delay(100);
    }
    assert.fail(`Production MCP server did not become ready:\n${fixture.output}`);
  } catch (error) {
    await cleanup();
    throw error;
  }
}, { timeout: 50_000 });

after(cleanup);

function rpc(method = "ping", params = {}, id = 1) {
  return { jsonrpc: "2.0", id, method, params };
}

async function raw(body = rpc(), { token = jwt(), headers = {}, method = "POST" } = {}) {
  return fetch(fixture.resource, {
    method,
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      ...(token === null ? {} : { authorization: `Bearer ${token}` }),
      ...headers,
    },
    ...(method === "POST" ? { body: typeof body === "string" ? body : JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(10_000),
  });
}

function newSdkClient(options = {}) {
  const client = new Client({ name: "rebstock-socket-tests", version: "1.0.0" });
  clients.add(client);
  const transport = new StreamableHTTPClientTransport(new URL(fixture.resource), options);
  return { client, transport };
}

async function connect(t, username = "socket-alice", options = {}) {
  const pair = newSdkClient({ requestInit: { headers: { authorization: `Bearer ${jwt(username)}` } }, ...options });
  t.after(async () => { await pair.client.close(); clients.delete(pair.client); });
  await pair.client.connect(pair.transport);
  return pair;
}

async function tool(client, name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  assert.equal(result.isError, false, `Tool ${name} failed`);
  assert.ok(result.structuredContent, `Tool ${name} must provide structured content`);
  assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent);
  return result.structuredContent;
}

function batch(source = "socket-invoice") {
  return {
    source,
    wines: [{ ref: "wine1", winery: "Socket Winery", name: "Riesling", wine_type: "WHITE", country: "DE", personal_note: "Private wine note", vintages: [{ year: "2023" }] }],
    cellar: [{ ref: "purchase1", wine_ref: "wine1", vintage: "2023", quantity: 3, date: "2026-11-08", price_cents: 1250, notes: "Invoice socket" }],
    ratings: [{ ref: "review1", wine_ref: "wine1", vintage: "2023", rating: 4.2, tasting_notes: "Keep exact notes", rated_at: "2026-11-08" }],
    wishlist: [{ ref: "wish1", wine_ref: "wine1", vintage: "2023", notes: "Try again" }],
  };
}

test("protected-resource discovery is public and advertises the OAuth issuer", async () => {
  for (const path of ["/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-protected-resource"]) {
    const response = await fetch(`${fixture.origin}${path}`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.deepEqual(await response.json(), {
      resource: fixture.resource,
      authorization_servers: [fixture.issuer],
      scopes_supported: [scope],
      bearer_methods_supported: ["header"],
      resource_name: "Rebstock MCP",
    });
  }
});

test("web Single authentication and forwarded identity cannot bypass the MCP bearer challenge", async () => {
  const response = await raw(rpc(), { token: null, headers: { "x-webauth-user": "socket-alice" } });
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const challenge = response.headers.get("www-authenticate");
  assert.ok(challenge.includes(`resource_metadata="${fixture.origin}/.well-known/oauth-protected-resource/mcp"`));
  assert.ok(challenge.includes(`scope="${scope}"`));
});

test("RSA signatures, audience, issuer, client, expiry, and scope are enforced over HTTP", async () => {
  const forgedKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
  const rejected = [
    ["malformed", "forged-token", 401],
    ["signature", jwt("socket-alice", {}, forgedKey), 401],
    ["audience", jwt("socket-alice", { aud: "http://127.0.0.1/other" }), 401],
    ["issuer", jwt("socket-alice", { iss: `${fixture.issuer}/other` }), 401],
    ["client", jwt("socket-alice", { client_id: "other-client" }), 401],
    ["expiry", jwt("socket-alice", { exp: Math.floor(Date.now() / 1000) - 1 }), 401],
    ["scope", jwt("socket-alice", { scope: "openid" }), 403],
  ];
  for (const [claim, token, status] of rejected) {
    const response = await raw(rpc(), { token });
    assert.equal(response.status, status, claim);
    await response.body?.cancel();
  }
  assert.equal((await raw()).status, 200);
});

test("the stateless transport rejects hostile origins and unsupported HTTP methods", async () => {
  assert.equal((await raw(rpc(), { headers: { origin: "https://hostile.example" } })).status, 403);
  assert.equal((await raw(rpc(), { headers: { origin: fixture.origin } })).status, 200);
  for (const method of ["GET", "DELETE"]) {
    const response = await raw(undefined, { method });
    assert.equal(response.status, 405);
    assert.match(response.headers.get("allow"), /POST/);
  }
});

test("the HTTP boundary enforces JSON, Accept, body size, and JSON-RPC parsing", async () => {
  assert.equal((await raw(rpc(), { headers: { "content-type": "text/plain" } })).status, 415);
  assert.equal((await raw(rpc(), { headers: { accept: "text/event-stream" } })).status, 406);
  assert.equal((await raw(" ".repeat(1_048_577))).status, 413);
  const malformed = await raw("{");
  assert.equal(malformed.status, 400);
  assert.equal((await malformed.json()).error.code, -32700);
});

test("the official SDK initializes, negotiates the latest protocol, and validates all eight tool schemas", async (t) => {
  const exchanges = [];
  const { client, transport } = await connect(t, "socket-catalog", {
    fetch: async (url, init) => {
      const request = init.body ? JSON.parse(init.body) : undefined;
      const response = await fetch(url, init);
      exchanges.push({
        method: init.method,
        rpcMethod: request?.method,
        proposal: request?.params?.protocolVersion,
        protocol: new Headers(init.headers).get("mcp-protocol-version"),
        status: response.status,
      });
      return response;
    },
  });
  assert.equal(LATEST_PROTOCOL_VERSION, "2025-11-25");
  assert.equal(transport.protocolVersion, LATEST_PROTOCOL_VERSION);
  assert.equal(transport.sessionId, undefined);
  assert.equal(client.getServerVersion().name, "Rebstock");
  assert.deepEqual(client.getServerCapabilities(), { tools: {} });
  const { tools } = await client.listTools();
  assert.deepEqual(tools.map(({ name }) => name).sort(), [
    "search_wines", "get_wine", "get_cellar", "get_ratings", "get_wishlist",
    "import_batch", "lookup_vivino_wine", "sync_vivino_ratings",
  ].sort());
  const validator = new AjvJsonSchemaValidator();
  const samples = {
    search_wines: { q: "Riesling", limit: 1, offset: 0 },
    get_wine: { wine_id: "owned-wine" },
    get_cellar: { wine_id: "owned-wine", limit: 1 },
    get_ratings: { wine_id: "owned-wine", limit: 1 },
    get_wishlist: { limit: 1 },
    import_batch: batch(),
    lookup_vivino_wine: { vivino_id: "123" },
    sync_vivino_ratings: { wine_ids: ["owned-wine"] },
  };
  for (const definition of tools) {
    assert.equal(definition.inputSchema.type, "object");
    assert.equal(definition.inputSchema.additionalProperties, false);
    assert.ok(definition.inputSchema.properties);
    assert.equal(typeof definition.annotations.readOnlyHint, "boolean");
    const validate = validator.getValidator(definition.inputSchema);
    const result = validate(samples[definition.name]);
    assert.equal(result.valid, true, `${definition.name}: ${result.errorMessage}`);
    assert.equal(validate({ ...samples[definition.name], unexpected: true }).valid, false);
  }
  assert.equal(tools.find(({ name }) => name === "search_wines").inputSchema.properties.limit.maximum, 100);
  assert.equal(tools.find(({ name }) => name === "import_batch").inputSchema.properties.apply.default, false);
  assert.ok(exchanges.some((item) => item.rpcMethod === "initialize" && item.proposal === LATEST_PROTOCOL_VERSION));
  assert.ok(exchanges.some((item) => item.rpcMethod === "tools/list" && item.protocol === LATEST_PROTOCOL_VERSION));
  assert.ok(exchanges.some((item) => item.method === "GET" && item.status === 405));
});

test("protocol initialization preserves supported older versions and falls back for a future proposal", async () => {
  for (const [requested, expected] of [["2025-03-26", "2025-03-26"], ["2099-01-01", "2025-11-25"]]) {
    const response = await raw(rpc("initialize", {
      protocolVersion: requested, capabilities: {}, clientInfo: { name: "socket-negotiation", version: "1" },
    }));
    assert.equal(response.status, 200);
    assert.equal((await response.json()).result.protocolVersion, expected);
  }
  const response = await raw(rpc(), { headers: { "mcp-protocol-version": "2099-01-01" } });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, -32600);
});

test("SDK preview, apply, retry, conflict, and reads preserve imported records exactly", async (t) => {
  const { client } = await connect(t);
  const preview = await tool(client, "import_batch", batch());
  assert.equal(preview.apply, false);
  assert.equal(preview.records.length, 4);
  assert.equal(preview.counts.bottles, 3);
  assert.deepEqual((await tool(client, "search_wines")).wines, []);
  assert.deepEqual((await tool(client, "get_cellar")).entries, []);
  assert.deepEqual((await tool(client, "get_ratings")).ratings, []);
  assert.deepEqual((await tool(client, "get_wishlist")).wishlist, []);
  const applied = await tool(client, "import_batch", { ...batch(), apply: true });
  assert.equal(applied.apply, true);
  assert.equal(applied.counts.created, 4);
  const wineId = applied.records.find(({ kind }) => kind === "wines").id;
  const retried = await tool(client, "import_batch", { ...batch(), apply: true });
  assert.equal(retried.counts.created, 0);
  assert.equal(retried.counts.unchanged, 4);
  assert.deepEqual(retried.records.map(({ id }) => id), applied.records.map(({ id }) => id));
  const changed = batch();
  changed.cellar[0].quantity = 4;
  changed.wines.push({ ref: "must-rollback", winery: "Socket Winery", name: "Must not persist" });
  const conflict = await client.callTool({ name: "import_batch", arguments: { ...changed, apply: true } });
  assert.equal(conflict.isError, true);
  const search = await tool(client, "search_wines", { q: "Socket Winery" });
  assert.equal(search.wines.length, 1);
  assert.equal(search.wines[0].id, wineId);
  const detail = await tool(client, "get_wine", { wine_id: wineId });
  assert.equal(detail.wine.name, "Riesling");
  assert.equal(detail.wine.country, "DE");
  assert.equal(detail.wine.wine_type, "WHITE");
  assert.equal(detail.wine.personal_note, "Private wine note");
  assert.deepEqual(detail.vintages.map(({ year }) => year), ["2023"]);
  const { entries } = await tool(client, "get_cellar", { wine_id: wineId });
  assert.equal(entries.length, 1);
  assert.deepEqual({ quantity: entries[0].quantity, vintage: entries[0].vintage, date: entries[0].date, price_cents: entries[0].price_cents, notes: entries[0].notes },
    { quantity: 3, vintage: "2023", date: "2026-11-08", price_cents: 1250, notes: "Invoice socket" });
  const { ratings } = await tool(client, "get_ratings", { wine_id: wineId });
  assert.equal(ratings.length, 1);
  assert.equal(ratings[0].rating, 4.2);
  assert.equal(ratings[0].tasting_notes, "Keep exact notes");
  assert.equal(ratings[0].rated_at, "2026-11-08");
  assert.deepEqual((await tool(client, "get_wishlist")).wishlist, [{ wine_id: wineId, winery: "Socket Winery", name: "Riesling", vintage: "2023", notes: "Try again" }]);
});

test("SDK read pagination advances without losing wines, purchases, ratings, or wishes", async (t) => {
  const { client } = await connect(t, "socket-pagination");
  const input = batch("socket-pagination");
  input.wines.push({ ...input.wines[0], ref: "wine2", name: "Silvaner" });
  for (const key of ["cellar", "ratings", "wishlist"]) {
    input[key].push({ ...input[key][0], ref: `${key}2`, wine_ref: "wine2" });
  }
  await tool(client, "import_batch", { ...input, apply: true });
  for (const [name, key] of [["search_wines", "wines"], ["get_cellar", "entries"], ["get_ratings", "ratings"], ["get_wishlist", "wishlist"]]) {
    const first = await tool(client, name, { limit: 1 });
    assert.equal(first[key].length, 1);
    assert.equal(first.next_offset, 1);
    const second = await tool(client, name, { limit: 1, offset: first.next_offset });
    assert.equal(second[key].length, 1);
    assert.equal(second.next_offset, null);
    assert.notDeepEqual(first[key][0], second[key][0]);
  }
});

test("a second bearer identity cannot read or mutate the first user's records", async (t) => {
  const owner = await connect(t, "socket-owner");
  const imported = await tool(owner.client, "import_batch", { ...batch("socket-ownership"), apply: true });
  const wineId = imported.records.find(({ kind }) => kind === "wines").id;
  const { client } = await connect(t, "socket-bob", {
    requestInit: { headers: { authorization: `Bearer ${jwt("socket-bob")}`, "x-webauth-user": "socket-owner" } },
  });
  for (const [name, key] of [["search_wines", "wines"], ["get_cellar", "entries"], ["get_ratings", "ratings"], ["get_wishlist", "wishlist"]]) {
    assert.deepEqual((await tool(client, name))[key], []);
  }
  assert.equal((await client.callTool({ name: "get_wine", arguments: { wine_id: wineId } })).isError, true);
  assert.deepEqual((await tool(client, "get_cellar", { wine_id: wineId })).entries, []);
  assert.deepEqual((await tool(client, "get_ratings", { wine_id: wineId })).ratings, []);
  const result = await client.callTool({ name: "import_batch", arguments: {
    source: "cross-user", apply: true,
    cellar: [{ ref: "purchase", wine_id: wineId, quantity: 99 }],
  } });
  assert.equal(result.isError, true);
  assert.deepEqual((await tool(client, "get_cellar")).entries, []);
  assert.equal((await tool(owner.client, "get_cellar")).entries[0].quantity, 3);
});

test("SDK tool errors reject invalid arguments without calling live Vivino", async (t) => {
  const { client } = await connect(t, "socket-errors");
  for (const [name, args] of [
    ["search_wines", { limit: 101 }],
    ["search_wines", { username: "socket-alice" }],
    ["import_batch", { source: "empty", apply: true }],
    ["lookup_vivino_wine", { vivino_id: "not-a-vivino-id" }],
    ["sync_vivino_ratings", { wine_ids: ["missing-owned-wine"] }],
  ]) {
    assert.equal((await client.callTool({ name, arguments: args })).isError, true, name);
  }
});

test("the SDK completes discovery and pre-registered authorization-code PKCE through a simulated browser callback", async (t) => {
  let savedTokens;
  let verifier;
  let discovery;
  let callbackCode;
  const state = randomBytes(24).toString("base64url");
  const provider = {
    redirectUrl: fixture.redirectUri,
    clientMetadata: {
      client_name: "Rebstock socket OAuth test", redirect_uris: [fixture.redirectUri],
      grant_types: ["authorization_code"], response_types: ["code"], token_endpoint_auth_method: "none", scope,
    },
    clientInformation: () => ({ client_id: clientId, issuer: fixture.issuer }),
    tokens: () => savedTokens,
    saveTokens: (tokens) => { savedTokens = tokens; },
    state: () => state,
    saveCodeVerifier: (value) => { verifier = value; },
    codeVerifier: () => verifier,
    saveDiscoveryState: (value) => { discovery = value; },
    discoveryState: () => discovery,
    redirectToAuthorization: async (url) => {
      const response = await fetch(url);
      assert.equal(response.status, 200);
      assert.equal(fixture.callback.searchParams.get("state"), state);
      callbackCode = fixture.callback.searchParams.get("code");
      assert.ok(callbackCode);
    },
  };
  const initial = newSdkClient({ authProvider: provider });
  t.after(async () => { await initial.client.close(); clients.delete(initial.client); });
  await assert.rejects(initial.client.connect(initial.transport), UnauthorizedError);
  assert.ok(callbackCode, "The simulated browser must return an authorization code");
  assert.equal(savedTokens, undefined);
  await initial.transport.finishAuth(callbackCode);
  assert.ok(savedTokens.access_token);
  assert.equal(savedTokens.issuer, fixture.issuer);
  const authenticated = await connect(t, "unused", { requestInit: undefined, authProvider: provider });
  assert.deepEqual((await tool(authenticated.client, "search_wines")).wines, []);
  assert.equal(fixture.authorizationRequests.length, 1);
  assert.equal(fixture.tokenRequests.length, 1);
  assert.ok(fixture.discoveryRequests.length >= 1);
  assert.equal(fixture.tokenRequests[0].pkceVerified, true);
  assert.equal(discovery.resourceMetadata.resource, fixture.resource);
  assert.equal(fixture.issuerFailure, undefined);
});
