const { test, expect } = require("@playwright/test");

async function seed(request) {
  const name = `Semantic Riesling ${Date.now()}`;
  const created = await request.post("/wines", {
    form: { name, winery: "Semantic Estate", vintage: "2023", country: "DE", wine_type: "white" },
    maxRedirects: 0,
  });
  expect(created.status()).toBe(303);
  const location = created.headers().location;
  const body = await (await request.get(location)).text();
  const wine = body.match(/href="([^"]+\/cellar\/new)"/)[1].replace("/cellar/new", "");
  return { name, wine, id: location.split("/").at(-1) };
}

async function checkHeadings(page) {
  const levels = await page.locator("main h1, main h2, main h3, main h4").evaluateAll(
    nodes => nodes.map(node => Number(node.tagName.slice(1))),
  );
  expect(levels[0]).toBe(1);
  expect(levels.filter(level => level === 1)).toHaveLength(1);
  levels.slice(1).forEach((level, index) => expect(level).toBeLessThanOrEqual(levels[index] + 1));
}

test("pages expose headings, collections, metadata, charts and dates natively", async ({ page, request }) => {
  const { name, wine, id } = await seed(request);
  const stocked = await request.post(`${wine}/cellar/new`, {
    form: { vintage: "2023", quantity: "3", price: "18.75", date: "2026-09-05" },
    maxRedirects: 0,
  });
  expect(stocked.status()).toBe(303);
  const rating = await request.post(`${wine}/ratings/new`, {
    form: { vintage: "2023", rating: "4.2", tasting_notes: "Notes by test", rated_at: "2026-09-05" },
    maxRedirects: 0,
  });
  expect(rating.status()).toBe(303);

  await page.goto("/");
  await checkHeadings(page);
  await expect(page.locator("dl.stats-grid dt")).toHaveCount(3);
  await expect(page.locator("dl.stats-grid dd")).toHaveCount(3);
  expect(await page.locator("ul.activity-list > li").count()).toBeGreaterThan(0);
  expect(await page.locator("figure.rating-chart figcaption").count()).toBeGreaterThan(0);
  for (const link of await page.locator(".rating-chart a").all()) {
    await expect(link).toHaveAttribute("aria-label", /^(You|Vivino) (unrated|[\d.]+) /);
  }
  await expect(page.getByRole("table", { name: "Cellar Quality — bottles" })).toBeAttached();
  for (const link of await page.locator(".section-heading a").all()) {
    await expect(link).toHaveAttribute("aria-label", /^View all: .+/);
  }

  await page.goto(wine);
  await checkHeadings(page);
  await expect(page.getByRole("heading", { name: "Ratings", exact: true, level: 2 })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Cellar", exact: true, level: 2 })).toBeVisible();
  await expect(page.getByRole("heading", { name: "You", exact: true, level: 3 })).toBeVisible();
  await expect(page.locator("dl.detail-grid dt")).toHaveText(["Country"]);
  await expect(page.locator("dl.detail-grid dd")).toHaveText(["Germany"]);
  await expect(page.locator("dl.wine-stats dt")).toHaveText(["Vivino", "You", "Others"]);
  expect(await page.locator('time[datetime="2026-09-05"]').count()).toBeGreaterThan(0);
  await expect(page.getByRole("link", { name: `Edit rating for ${name}, 05.09.2026`, exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: `Edit cellar entry for ${name}, 05.09.2026`, exact: true })).toBeVisible();

  const vintages = page.getByRole("navigation", { name: "Filter by vintage" });
  await expect(vintages.locator('[aria-current="true"]')).toHaveText("All");
  await vintages.getByRole("link", { name: "2023", exact: true }).click();
  await expect(vintages.locator('[aria-current="true"]')).toHaveText("2023");
  await expect(vintages.locator('[aria-current="true"]')).toHaveCount(1);
  const ratingEdit = await page.locator('a[href*="/ratings/"][href$="/edit"]').getAttribute("href");
  const cellarEdit = await page.locator('a[href*="/cellar/"][href$="/edit"]').getAttribute("href");
  const drink = await page.locator('a[href$="/drink"]').getAttribute("href");
  for (const path of [`${wine}/cellar/new`, `${wine}/ratings/new`, ratingEdit, cellarEdit, drink]) {
    await page.goto(path);
    await checkHeadings(page);
  }
  await page.goto(wine);
  await page.getByRole("link", { name: "Add to cellar", exact: true }).click();
  await expect(page.getByRole("dialog").getByRole("heading", { name: "Add to Cellar", level: 2 })).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();

  await page.goto(`${wine}/edit`);
  await expect(page.getByLabel("Label Photo")).toHaveAccessibleDescription("Portrait orientation, ideally 300×400px or larger");
  const createdList = await request.post("/~test/lists", { form: { name: `Semantic list ${Date.now()}` }, maxRedirects: 0 });
  expect(createdList.status()).toBe(303);
  const list = createdList.headers().location;
  expect((await request.post(`${list}/wines`, { form: { wine_id: id, vintage: "2023" }, maxRedirects: 0 })).status()).toBe(303);
  expect((await request.post(`${list}/public`, { form: { public: "1" }, maxRedirects: 0 })).status()).toBe(303);
  await page.goto("/~test/lists");
  expect(await page.locator("ul.list-grid > li h2").count()).toBeGreaterThan(0);
  await page.goto(list);
  await expect(page.getByRole("columnheader", { name: "Actions" })).toBeAttached();
  await expect(page.getByRole("button", { name: `Remove ${name} (2023) from list`, exact: true })).toBeVisible();
  const shared = await page.getByRole("link", { name: "Open shared wine list" }).getAttribute("href");
  await page.goto(shared);
  await checkHeadings(page);
  await expect(page.locator("main")).toHaveCount(1);
  await expect(page.locator("main > header h1")).toBeVisible();
  await expect(page.locator("main section h2")).toHaveText(["White"]);
  await expect(page.locator("ul.wine-items > li")).toHaveCount(1);
  await expect(page.getByRole("contentinfo")).toBeVisible();
  expect((await request.post(`${list}/public`, { form: { public: "0" }, maxRedirects: 0 })).status()).toBe(303);
  expect((await page.goto(shared)).status()).toBe(404);
  await expect(page.getByRole("main")).toBeVisible();
});

test("table enhancements preserve native link behavior", async ({ page, context, request, browserName }) => {
  const { name } = await seed(request);
  await page.goto("/wines");
  await page.getByRole("searchbox").fill(name);
  const row = page.locator("tbody tr:visible");
  const link = row.locator('a[href^="/wineries/"]');
  const destination = await link.getAttribute("href");
  // Headless WebKit on macOS does not open native middle-click tabs.
  // Exercise the actual default action in Chromium and the handler guard in both.
  if (browserName === "chromium") {
    const opened = context.waitForEvent("page");
    await link.click({ button: "middle" });
    const popup = await opened;
    await popup.waitForURL(`http://127.0.0.1:4101${destination}`);
    expect(context.pages()).toHaveLength(2);
    await popup.close();
  }

  // The enhancement must also ignore nested text and form controls.
  const results = await row.evaluate(element => {
    const opened = [];
    const original = window.open;
    window.open = url => { opened.push(url); return null; };
    try {
      const name = element.querySelector('a[href^="/wines/"]');
      const child = document.createElement("span");
      name.append(child);
      child.dispatchEvent(new MouseEvent("auxclick", { button: 1, bubbles: true }));
      const button = document.createElement("button");
      element.lastElementChild.append(button);
      button.dispatchEvent(new MouseEvent("auxclick", { button: 1, bubbles: true }));
      element.lastElementChild.dispatchEvent(new MouseEvent("auxclick", { button: 1, bubbles: true }));
      button.remove();
      child.remove();
      return opened;
    } finally {
      window.open = original;
    }
  });
  expect(results).toHaveLength(1);
});
