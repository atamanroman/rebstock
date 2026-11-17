const assert = require("node:assert/strict");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { spawn, execFileSync } = require("node:child_process");
const { chromium, request, expect } = require("@playwright/test");

const repository = path.resolve(__dirname, "../..");
const root = path.join(repository, "docs/artwork-collection");
// Fictitious demonstration data, including the illustrative community scores.
const fixtures = [
  ["Cascina del Bosco", "Langhe Nebbiolo", "Red", "IT", "Piedmont", "2022", 6, "24.50", "4.5", "Red cherry, rose petals and fine tannins. Fresh and elegant with a long, savory finish."],
  ["Weingut Steinbach", "Riesling Kabinett", "White", "DE", "Mosel", "2023", 6, "18.00", "4.2", "Lime, white peach and slate, with bright acidity and a delicate touch of sweetness."],
  ["Domaine Saint Clair", "Côtes de Provence", "Rose", "FR", "Provence", "2024", 4, "16.50", "4.0", "Wild strawberry and citrus. Dry, crisp and lovely with lunch outside."],
  ["Cellier des Coteaux", "Blanc de Blancs Brut", "Sparkling", "FR", "Champagne", "", 3, "42.00", "4.5", "Fine bubbles, green apple and a little brioche. A lively, mineral finish."],
  ["Kvareli Family Cellar", "Rkatsiteli Qvevri", "Orange", "GE", "Kakheti", "2022", 4, "22.50", "4.1", "Apricot skin, tea and dried herbs. Gentle grip and a generous, textured palate."],
  ["Weingut Abendrot", "Ortega Beerenauslese", "Dessert", "DE", "Rheinhessen", "2021", 2, "28.00", "4.4", "Honey and candied apricot, balanced by clean acidity. Saved for a special dessert."],
  ["Tsukino", "Junmai Ginjo", "Sake", "JP", "Niigata", "", 2, "32.00", "4.2", "Melon, pear and soft rice notes. Smooth, delicate and quietly complex."],
  ["Bodega del Sol", "Vermut Rojo", "Other", "ES", "Jerez", "", 1, "22.00", "4.0", "Orange peel, warm spice and bittersweet herbs. Ready for the next aperitivo."],
  ["Domaine La Rive", "Bourgogne Pinot Noir", "Red", "FR", "Burgundy", "2022", 5, "32.00", "4.4", "Red berries and forest floor, silky tannins and lovely freshness."],
  ["Tenuta della Collina", "Soave Classico", "White", "IT", "Veneto", "2023", 6, "15.50", "4.1", "Pear, almond and white flowers. An easy favorite with a mineral finish."],
];

function date(monthsAgo, day = 10) {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - monthsAgo, day)).toISOString().slice(0, 10);
}

async function freePort() {
  const socket = net.createServer();
  await new Promise((resolve, reject) => { socket.once("error", reject); socket.listen(0, "127.0.0.1", resolve); });
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}

async function stop(server) {
  if (!server?.pid || server.exitCode !== null || server.signalCode !== null) return;
  const exited = new Promise(resolve => server.once("exit", resolve));
  process.kill(-server.pid, "SIGTERM");
  const timeout = setTimeout(() => { try { process.kill(-server.pid, "SIGKILL"); } catch {} }, 3000);
  try { await exited; } finally { clearTimeout(timeout); }
}

(async () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "rebstock-screenshots-"));
  let server, browser, api;
  try {
    const port = await freePort();
    const baseURL = `http://127.0.0.1:${port}`;
    const database = path.join(scratch, "demo.db");
    const imageDirectory = path.join(scratch, "images");
    const config = path.join(scratch, "config.json");
    fs.mkdirSync(imageDirectory);
    fs.writeFileSync(config, JSON.stringify({
      host: "127.0.0.1", port, database_uri: `file:${database}`, image_dir: imageDirectory,
      secret_key_base: "screenshot-demo-secret-key-base-0123456789",
      auth: { forward: { header_user: "x-screenshot-user" } },
    }));
    const log = path.join(scratch, "server.log");
    const logFile = fs.openSync(log, "w");
    let startupError;
    server = spawn("gleam", ["run", "--", "--config", config], { cwd: repository, detached: true, stdio: ["ignore", logFile, logFile] });
    fs.closeSync(logFile);
    server.on("error", error => { startupError = error; });
    api = await request.newContext({ baseURL, extraHTTPHeaders: { "x-screenshot-user": "demo" } });
    await expect.poll(async () => {
      if (startupError) throw startupError;
      if (server.exitCode !== null) throw new Error(fs.readFileSync(log, "utf8"));
      try { return (await api.get("/", { timeout: 1000 })).status(); } catch { return 0; }
    }, { timeout: 30000 }).toBe(200);

    async function post(url, form) {
      const response = await api.post(url, { form, maxRedirects: 0 });
      assert.equal(response.status(), 303, `${url}: ${await response.text()}`);
      return response.headers().location;
    }

    const wines = [];
    for (const [index, fixture] of fixtures.entries()) {
      const [winery, name, wine_type, country, region, vintage, quantity, price, rating, tasting_notes] = fixture;
      const location = await post("/wines", { winery, name, wine_type, country, region, vintage, personal_note: index === 0 ? "A favorite for autumn dinners. Keep a couple of bottles to revisit next year." : "" });
      const response = await api.get(location);
      assert.equal(response.status(), 200);
      const action = (await response.text()).match(/href="([^"]+\/cellar\/new)"/);
      assert.ok(action, "Wine detail must expose its canonical cellar action");
      const url = action[1].replace(/\/cellar\/new$/, "");
      const id = url.split("/")[2];
      assert.match(id, /^[0-9A-Z]{26}$/);
      await post(`${url}/cellar/new`, { vintage, quantity, price, date: date(index % 6 + 1), notes: "Bought at the winery" });
      await post(`${url}/ratings/new`, { vintage, rating, tasting_notes, rated_at: date(index % 5, 12) });
      wines.push({ url, id, vintage, rating });
    }
    // Only the disposable database is touched; no live Vivino requests are made.
    execFileSync("sqlite3", [database, "BEGIN;" + wines.map((wine, index) => {
      const score = (Number(wine.rating) - (index % 2 ? 0.1 : 0.2)).toFixed(1);
      return `UPDATE wines SET vivino_rating=${score}, vivino_rating_count=240 WHERE id='${wine.id}'; UPDATE wines_vintages SET vivino_rating=${score}, vivino_rating_count=120 WHERE wine_id='${wine.id}';`;
    }).join("") + `INSERT INTO wines_vintages (wine_id, year, vivino_rating, vivino_rating_count) VALUES ('${wines[0].id}', '2021', 4.3, 180); COMMIT;`]);
    await post(`${wines[0].url}/cellar/new`, { vintage: "2021", quantity: 2, price: "27.00", date: date(2), notes: "Two bottles from an older vintage" });
    await post(`${wines[0].url}/ratings/new`, { vintage: "2021", rating: "4.3", rated_at: date(1), tasting_notes: "More savory and settled than the younger vintage, with dried cherry and a hint of leather." });

    browser = await chromium.launch();
    const context = await browser.newContext({ baseURL, viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, colorScheme: "light", locale: "en-GB", timezoneId: "UTC", extraHTTPHeaders: { "x-screenshot-user": "demo" } });
    await context.route("**/*", route => new URL(route.request().url()).origin === baseURL ? route.continue() : route.abort());
    const page = await context.newPage();
    await page.goto(wines[0].url);
    const drink = await page.locator('a[href$="/drink"]').first().getAttribute("href");
    assert.ok(drink);
    await post(drink, { date: date(0), notes: "Opened with dinner" });
    const list = await post("/~demo/lists", { name: "Autumn table", description: "A few bottles to share over dinner.", show_bottles: "1" });
    for (const index of [0, 8, 1, 9, 2, 3]) await post(`${list}/wines`, { wine_id: wines[index].id, vintage: wines[index].vintage });
    await post(`${list}/public`, { public: "1" });
    await page.goto(list);
    const shared = await page.getByRole("link", { name: "Open shared wine list" }).getAttribute("href");
    assert.ok(shared);
    assert.equal((await api.get(shared, { headers: { "x-screenshot-user": "" } })).status(), 200);

    const captures = [
      ["dashboard.png", "/", 1280, "screen"],
      ["wine.png", wines[0].url, 1280, "screen"],
      ["cellar.png", "/~demo/cellar", 1280, "screen"],
      ["cellar-mobile.png", "/~demo/cellar", 375, "screen"],
      ["shared-list.png", shared, 1100, "screen"],
      ["cellar-print.png", `${list}/print`, 1100, "print"],
    ];
    for (const [filename, url, width, media] of captures) {
      await page.setViewportSize({ width, height: 900 });
      await page.emulateMedia({ media });
      const response = await page.goto(url);
      assert.equal(response.status(), 200);
      await page.evaluate(() => document.fonts.ready);
      // Missing uploaded photos are hidden by the app in favor of the SVG fallback.
      await page.waitForFunction(() => [...document.querySelectorAll("img[src]")].every(image => !image.getClientRects().length || (image.complete && image.naturalWidth > 0)));
      if (filename === "wine.png") await expect(page.getByRole("img", { name: "Red wine bottle illustration", exact: true })).toBeVisible();
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${filename}: no overflow`);
      await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
      const violations = await page.evaluate(async () => (await axe.run({ runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] } })).violations.map(violation => ({ id: violation.id, targets: violation.nodes.map(node => node.target) })));
      assert.deepEqual(violations, [], filename);
      await page.screenshot({ path: path.join(scratch, filename), fullPage: true, animations: "disabled", caret: "hide" });
      console.log(`Captured ${filename}: ${width}px, ${media}, HTTP/image/axe checks passed`);
    }
    fs.mkdirSync(path.join(root, "assets"), { recursive: true });
    for (const [filename] of captures) fs.copyFileSync(path.join(scratch, filename), path.join(root, "assets", filename));
    for (const [source, destination] of [["dashboard.png", "dashboard.png"], ["shared-list.png", "cellar.png"]]) {
      fs.copyFileSync(path.join(scratch, source), path.join(repository, "site/static/images", destination));
    }
    console.log("Updated six documentation screenshots and both project-site copies; real cellar data untouched.");
  } finally {
    await browser?.close();
    await api?.dispose();
    await stop(server);
    fs.rmSync(scratch, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
