const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./test/browser",
  workers: 1,
  timeout: 45_000,
  use: {
    baseURL: "http://127.0.0.1:4101",
    extraHTTPHeaders: { "x-test-user": "test" },
    viewport: { width: 375, height: 812 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "chromium", use: { browserName: "chromium" } },
    { name: "webkit", use: { browserName: "webkit" } },
  ],
  webServer: {
    command: "node test/browser/server.cjs",
    url: "http://127.0.0.1:4101",
    reuseExistingServer: false,
    gracefulShutdown: { signal: "SIGTERM", timeout: 5000 },
    timeout: 30_000,
  },
});
