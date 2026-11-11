const { mkdtempSync, mkdirSync, writeFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { spawn } = require("node:child_process");

const directory = mkdtempSync(join(tmpdir(), "rebstock-browser-"));
mkdirSync(join(directory, "images"));
const config = join(directory, "config.json");
writeFileSync(
  config,
  JSON.stringify({
    host: "127.0.0.1",
    port: 4101,
    database_uri: `file:${join(directory, "test.db")}`,
    image_dir: join(directory, "images"),
    secret_key_base: "browser-test-secret-key-base-0123456789",
    auth: { forward: { header_user: "x-test-user" } },
  }),
);
const server = spawn("gleam", ["run", "--", "--config", config], {
  stdio: "inherit",
  detached: true,
});
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => process.kill(-server.pid, signal));
}
server.on("exit", (code) => {
  rmSync(directory, { recursive: true, force: true });
  process.exit(code ?? 0);
});
