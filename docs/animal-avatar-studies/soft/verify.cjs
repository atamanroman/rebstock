const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { chromium, webkit } = require("@playwright/test");

const root = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
const sources = manifest.candidates.map(candidate => fs.readFileSync(path.join(root, candidate.file), "utf8"));
assert.equal(sources.length, 3);
assert.equal(new Set(sources).size, 3);
const productionHash = () => crypto.createHash("sha256").update(fs.readFileSync(path.join(root, manifest.production_avatar))).digest("hex");
assert.equal(productionHash(), manifest.production_sha256);

async function verify(name, engine) {
  const browser = await engine.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1240, height: 1100 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.goto(pathToFileURL(path.join(root, "index.html")).href);
    await page.waitForFunction(() => document.images.length === 9 && [...document.images].every(img => img.complete && img.naturalWidth > 0));
    assert.deepEqual(await page.evaluate(sources => sources.map(source => {
      const doc = new DOMParser().parseFromString(source, "image/svg+xml");
      return {
        valid: !doc.querySelector("parsererror") && doc.documentElement.localName === "svg",
        viewBox: doc.documentElement.getAttribute("viewBox"),
        title: !!doc.querySelector("title")?.textContent,
        unsafe: !!doc.querySelector("script, foreignObject, image, text, filter, style, animate, set, use"),
        external: [...doc.querySelectorAll("*")].some(node => [...node.attributes].some(attr =>
          /^on/i.test(attr.name) || (["href", "xlink:href"].includes(attr.name) && !attr.value.startsWith("#")))),
      };
    }), sources), sources.map(() => ({ valid: true, viewBox: "0 0 240 240", title: true, unsafe: false, external: false })));
    await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
    for (const width of [1240, 768, 375, 320]) {
      await page.setViewportSize({ width, height: 1100 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `No overflow at ${width}px`);
      assert.deepEqual(await page.locator(".profile").evaluateAll(images => images.map(img => [img.clientWidth, img.clientHeight])), [[96, 96], [96, 96], [96, 96]]);
      assert.deepEqual(await page.locator(".menu").evaluateAll(images => images.map(img => [img.clientWidth, img.clientHeight])), [[28, 28], [28, 28], [28, 28]]);
      const violations = await page.evaluate(async () => (await axe.run({
        runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] },
      })).violations.map(v => ({ id: v.id, nodes: v.nodes.map(node => node.failureSummary) })));
      assert.deepEqual(violations, []);
      if (name === "chromium" && width === 1240) {
        fs.mkdirSync(path.join(root, "previews"), { recursive: true });
        await page.screenshot({ path: path.join(root, "previews/contact-sheet.png"), fullPage: true });
      }
    }
    for (const candidate of manifest.candidates) {
      const response = await page.goto(pathToFileURL(path.join(root, candidate.file)).href);
      assert.ok(response.ok());
      assert.equal(await page.locator("svg").count(), 1);
    }
    assert.deepEqual(errors, []);
    console.log(`${name}: three safe SVGs, rendering, 96/28px samples, mobile and axe passed`);
  } finally {
    await browser.close();
  }
}

(async () => {
  await verify("chromium", chromium);
  await verify("webkit", webkit);
  assert.equal(productionHash(), manifest.production_sha256);
  console.log("Production avatar unchanged.");
})().catch(error => { console.error(error); process.exitCode = 1; });
