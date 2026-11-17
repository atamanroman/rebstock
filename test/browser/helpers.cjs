const { expect } = require("@playwright/test");

let sequence = 0;

async function seed(request, wineType = "white") {
  const name = `Journal Riesling ${Date.now()} ${++sequence}`;
  const created = await request.post("/wines", {
    form: {
      name,
      winery: "Journal Estate",
      vintage: "2023",
      country: "DE",
      wine_type: wineType,
    },
    maxRedirects: 0,
  });
  expect(created.status()).toBe(303);
  const location = created.headers().location;
  const html = await (await request.get(location)).text();
  const action = html.match(/href="([^"]+\/cellar\/new)"/);
  expect(action, "Wine detail must expose its canonical cellar action").not.toBeNull();
  return {
    wine: action[1].replace("/cellar/new", ""),
    name,
    id: location.split("/").at(-1),
  };
}

async function noOverflow(page) {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    page.url(),
  ).toBe(true);
}

async function accessible(page) {
  await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
  const violations = await page.evaluate(async () => (
    await axe.run({ runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] } })
  ).violations.map(violation => ({
    id: violation.id,
    nodes: violation.nodes.map(node => ({ target: node.target, summary: node.failureSummary })),
  })));
  expect(violations, page.url()).toEqual([]);
}

module.exports = { seed, noOverflow, accessible };
