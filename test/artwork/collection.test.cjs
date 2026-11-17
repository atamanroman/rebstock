const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { fileURLToPath, pathToFileURL } = require("node:url");
const { chromium, webkit } = require("@playwright/test");

const repository = path.resolve(__dirname, "../..");
const root = path.join(repository, "docs/artwork-collection");
const bottles = ["red", "white", "rose", "orange", "sparkling", "dessert", "sake", "other"]
  .map(type => `${type}.svg`).sort();
const pages = ["index.html", "current-bottles.html", "current-logo.html"];

function localLinkExists(value, source) {
  const url = new URL(value, pathToFileURL(source));
  if (url.protocol === "file:") {
    assert.ok(fs.existsSync(fileURLToPath(url)), `${source}: missing local link ${value}`);
  }
}

function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? markdownFiles(filename) : entry.name.endsWith(".md") ? [filename] : [];
  });
}

test("artwork documentation and screenshot links resolve locally", () => {
  for (const filename of [path.join(repository, "README.md"), path.join(repository, "docs/ui.md"), ...markdownFiles(root)]) {
    const source = fs.readFileSync(filename, "utf8");
    for (const match of source.matchAll(/\b(?:src|href)=["']([^"']+)["']|\[[^\]]*\]\(([^\s)]+)\)/g)) {
      localLinkExists(match[1] || match[2], filename);
    }
  }
});

test("project-site screenshots match the current captures", () => {
  for (const [source, destination] of [["dashboard.png", "dashboard.png"], ["shared-list.png", "cellar.png"]]) {
    assert.ok(
      fs.readFileSync(path.join(root, "assets", source)).equals(fs.readFileSync(path.join(repository, "site/static/images", destination))),
      `Project site screenshot must match ${source}`,
    );
  }
});

for (const [name, engine] of [["chromium", chromium], ["webkit", webkit]]) {
  test(`${name}: previews show all eight bottles, load media and remain accessible`, { timeout: 60000 }, async () => {
    const browser = await engine.launch();
    try {
      const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
      const errors = [];
      page.on("pageerror", error => errors.push(error.message));
      for (const filename of pages) {
        const source = path.join(root, filename);
        await page.goto(pathToFileURL(source).href);
        await page.waitForFunction(() => [...document.querySelectorAll("img[src]")].every(image => image.complete && image.naturalWidth > 0));
        const links = await page.locator("[href], [src]").evaluateAll(nodes => nodes.flatMap(node =>
          ["href", "src"].filter(attribute => node.hasAttribute(attribute)).map(attribute => node.getAttribute(attribute))));
        for (const link of links) localLinkExists(link, source);
        assert.deepEqual(
          (await page.locator(".bottles img").evaluateAll(images => images.map(image => new URL(image.src).pathname.split("/").pop()))).sort(),
          bottles,
          `${filename}: the complete production bottle set must be visible`,
        );
        await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
        for (const width of [1440, 768, 375, 320]) {
          await page.setViewportSize({ width, height: 1100 });
          assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${filename}: overflow at ${width}px`);
          const violations = await page.evaluate(async () => (await axe.run({
            runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] },
          })).violations.map(violation => ({ id: violation.id, targets: violation.nodes.map(node => node.target) })));
          assert.deepEqual(violations, [], `${filename}: accessibility at ${width}px`);
        }
      }
      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
    }
  });
}
