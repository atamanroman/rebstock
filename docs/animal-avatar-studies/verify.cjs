const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { chromium, webkit } = require("@playwright/test");

const root = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
const sources = manifest.candidates.map(candidate => fs.readFileSync(path.join(root, candidate.file), "utf8"));
assert.equal(manifest.candidates.length, 12);
assert.equal(new Set(sources.map(svg => crypto.createHash("sha256").update(svg).digest("hex"))).size, 12);
assert.equal(new Set(manifest.candidates.map(candidate => candidate.id)).size, 12);
assert.deepEqual(manifest.candidates.map(candidate => candidate.number), Array.from({ length: 12 }, (_, i) => String(i + 1).padStart(2, "0")));
for (const species of manifest.species) assert.equal(manifest.candidates.filter(candidate => candidate.species === species.id).length, 4);
const productionHash = () => crypto.createHash("sha256").update(fs.readFileSync(path.join(root, manifest.production_avatar))).digest("hex");
assert.equal(productionHash(), manifest.production_sha256, "Production avatar must remain unchanged");

async function accessible(page) {
  const violations = await page.evaluate(async () => (await axe.run({
    runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] },
  })).violations.map(v => ({ id: v.id, nodes: v.nodes.map(node => node.failureSummary) })));
  assert.deepEqual(violations, []);
}

async function verify(name, engine) {
  const browser = await engine.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.goto(pathToFileURL(path.join(root, "index.html")).href);
    await page.waitForFunction(() => document.querySelectorAll(".candidate").length === 12
      && [...document.querySelectorAll(".candidate img, .comparison img")].every(img => img.complete && img.naturalWidth > 0));
    assert.deepEqual(await page.evaluate(sources => sources.map(source => {
      const doc = new DOMParser().parseFromString(source, "image/svg+xml");
      return {
        valid: !doc.querySelector("parsererror") && doc.documentElement.localName === "svg",
        viewBox: doc.documentElement.getAttribute("viewBox"),
        title: !!doc.querySelector("title")?.textContent,
        glassCount: doc.querySelectorAll(".wine-glass").length,
        thinGlass: [...doc.querySelectorAll(".wine-glass [stroke-width]")].every(node => Number(node.getAttribute("stroke-width")) <= 1.4),
        unsafe: !!doc.querySelector("script, foreignObject, image, text, filter, style, animate, set, use"),
        external: [...doc.querySelectorAll("*")].some(node => [...node.attributes].some(attr =>
          /^on/i.test(attr.name) || (["href", "xlink:href"].includes(attr.name) && !attr.value.startsWith("#")))),
      };
    }), sources), sources.map(() => ({ valid: true, viewBox: "0 0 120 120", title: true, glassCount: 1, thinGlass: true, unsafe: false, external: false })));
    assert.deepEqual(await page.locator(".samples .profile").evaluateAll(images => images.map(img => [img.clientWidth, img.clientHeight])), Array.from({ length: 12 }, () => [96, 96]));
    assert.deepEqual(await page.locator(".samples .menu").evaluateAll(images => images.map(img => [img.clientWidth, img.clientHeight])), Array.from({ length: 12 }, () => [28, 28]));
    await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
    await accessible(page);

    if (name === "chromium") {
      const previews = path.join(root, "previews");
      fs.mkdirSync(previews, { recursive: true });
      await page.screenshot({ path: path.join(previews, "contact-sheet.png"), fullPage: true });
      for (const species of manifest.species) {
        await page.locator(`[data-species="${species.id}"]`).screenshot({ path: path.join(previews, species.id + ".png") });
      }
    }
    await page.locator("#actual-size").check();
    assert.equal(await page.locator(".artboard img").first().evaluate(img => img.clientWidth), 96);
    await page.locator("#actual-size").uncheck();
    assert.equal(await page.locator(".artboard img").first().evaluate(img => img.clientWidth), 168);

    for (const species of manifest.species) {
      await page.locator("#species-filter").selectOption(species.id);
      assert.equal(await page.locator(".candidate:visible").count(), 4);
      assert.equal(await page.locator(".study-section:visible").getAttribute("data-species"), species.id);
      await accessible(page);
    }
    await page.locator("#species-filter").selectOption("all");
    assert.equal(await page.locator(".candidate:visible").count(), 12);

    for (const candidate of manifest.candidates) {
      const card = page.locator("#" + candidate.id.toLowerCase());
      await card.locator(".artboard").click();
      assert.equal(await page.locator("#preview").evaluate(dialog => dialog.open), true);
      assert.equal(await page.locator("#close-preview").evaluate(button => button === document.activeElement), true);
      assert.ok((await page.locator("#preview-heading").innerText()).includes(candidate.name));
      if (candidate.number === "01") await accessible(page);
      await page.keyboard.press("Escape");
      assert.equal(await page.locator("#preview").evaluate(dialog => dialog.open), false);
      assert.equal(await card.locator(".artboard").evaluate(button => button === document.activeElement), true);
    }

    await page.locator('input[value="DACHSHUND-01"]').check();
    await page.reload();
    await page.waitForFunction(() => document.querySelector('input[value="DACHSHUND-01"]')?.checked);
    assert.ok((await page.locator("#selection-status").innerText()).includes("DACHSHUND-01"));
    await page.locator("#copy-selection").click();
    await page.waitForFunction(() => document.getElementById("selection-status").textContent.includes("DACHSHUND-01"));
    await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
    for (const width of [320, 375, 768]) {
      await page.setViewportSize({ width, height: 812 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `No overflow at ${width}px`);
      await accessible(page);
    }
    assert.deepEqual(errors, []);
    console.log(`${name}: 12 SVGs; rendering, 96/28px sizes, filters, selection, dialog, mobile and axe passed`);
  } finally {
    await browser.close();
  }
}

(async () => {
  await verify("chromium", chromium);
  await verify("webkit", webkit);
  assert.equal(productionHash(), manifest.production_sha256);
  console.log("Production avatar unchanged; all twelve animal studies verified.");
})().catch(error => { console.error(error); process.exitCode = 1; });
