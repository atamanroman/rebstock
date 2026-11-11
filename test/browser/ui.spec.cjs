const { test, expect } = require("@playwright/test");

let sequence = 0;
async function seed(request) {
  const name = `Journal Riesling ${Date.now()} ${++sequence}`;
  const created = await request.post("/wines", {
    form: {
      name,
      winery: "Journal Estate",
      vintage: "2023",
      country: "DE",
      wine_type: "white",
    },
    maxRedirects: 0,
  });
  expect(created.status()).toBe(303);
  const path = created.headers().location;
  const html = await (await request.get(path)).text();
  const wine = html
    .match(/href="([^"]+\/cellar\/new)"/)[1]
    .replace("/cellar/new", "");
  return { wine, name, id: path.split("/").at(-1) };
}
async function stock(request, wine, quantity = "3") {
  const response = await request.post(`${wine}/cellar/new`, {
    form: { vintage: "2023", quantity, price: "18.75", date: "2026-09-05" },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(303);
  const html = await (await request.get(wine)).text();
  return html.match(/href="([^"]+\/cellar\/[^/]+\/drink)"/)[1];
}
async function noOverflow(page) {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
    page.url(),
  ).toBe(true);
}
async function accessible(page) {
  await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
  const violations = await page.evaluate(async () =>
    (
      await axe.run({
        runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] },
      })
    ).violations.map((v) => ({
      id: v.id,
      nodes: v.nodes.map((n) => ({
        target: n.target,
        summary: n.failureSummary,
      })),
    })),
  );
  expect(violations, page.url()).toEqual([]);
}
function drinkLink(page) {
  return page.getByRole("link", { name: /^Drink cellar entry for / });
}
async function open(page, label) {
  const link = label === "Drink" ? drinkLink(page) : page.getByRole("link", { name: label, exact: true });
  await link.click();
  await expect(page.getByRole("dialog")).toBeFocused();
}
async function saved(page, wine) {
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page).toHaveURL(`http://127.0.0.1:4101${wine}`);
}

test("Ledger uses directly served CSS and restrained wine labels", async ({
  page,
  request,
}) => {
  for (const file of ["app.css", "ui.css", "layout.css", "colors.css"]) {
    const response = await request.get(`/static/css/${file}`);
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("text/css");
    expect(await response.text()).not.toMatch(/@theme|@tailwind|tailwindcss/);
  }
  const { wine } = await seed(request);
  await page.goto(wine);
  await expect(page.locator("html")).toHaveAttribute("data-ui", "ledger");
  await expect(page.locator("body")).toHaveCSS("background-color", "rgb(255, 255, 255)");
  await expect(page.locator(".brand")).toHaveAccessibleName("Rebstock");
  await expect(page.locator(".brand-mark")).toBeVisible();
  await expect(page.locator(".brand-mark")).toHaveAttribute("alt", "");
  expect(await page.locator(".brand-mark").evaluate(image => image.complete && image.naturalWidth > 0)).toBe(true);
  await expect(page.locator(".brand-description")).toHaveCount(0);
  await expect(page.locator(".wine-type").first()).toHaveText("White");
  await expect(page.locator(".wine-type").first()).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  await expect(page.locator("h1")).toHaveCSS("font-family", /system-ui/);
});

test("empty collections and filters have useful feedback", async ({
  page,
  request,
}) => {
  const empty = `empty-${Date.now()}`;
  await request.get("/", { headers: { "x-test-user": empty } });
  for (const suffix of ["", "/cellar", "/ratings", "/wishlist", "/lists"]) {
    expect((await page.goto(`/~${empty}${suffix}`)).status()).toBe(200);
    await noOverflow(page);
    await accessible(page);
  }
  await page.goto("/wines");
  await page.getByRole("searchbox").fill("no-such-wine-unique");
  await expect(page.locator("tbody tr:visible")).toHaveCount(0);
  await expect(page.locator(".table-empty")).toBeVisible();
});

test("all populated screens fit mobile through desktop and pass axe", async ({
  page,
  request,
}) => {
  test.setTimeout(180_000);
  const { wine, name, id } = await seed(request);
  const drink = await stock(request, wine);
  await request.post(`${wine}/ratings/new`, {
    form: {
      vintage: "2023",
      rating: "4.2",
      tasting_notes: "Lemon and slate",
      rated_at: "2026-09-05",
    },
  });
  const created = await request.post("/~test/lists", {
    form: {
      name: `Dinner with friends ${Date.now()}`,
      description:
        "A deliberately long description that must wrap without pushing the page beyond a narrow screen.",
      show_bottles: "1",
    },
    maxRedirects: 0,
  });
  const list = created.headers().location;
  await request.post(`${list}/wines`, {
    form: { wine_id: id, vintage: "2023" },
  });
  await request.post(`${list}/public`, { form: { public: "1" } });
  await page.goto(wine);
  const notes = await page
    .getByText("Lemon and slate", { exact: true })
    .boundingBox();
  const editRating = await page
    .locator('a[href*="/ratings/"][href$="/edit"]')
    .boundingBox();
  expect(notes.y).toBeGreaterThanOrEqual(editRating.y + editRating.height);
  const winery = await page
    .locator('main a[href^="/wineries/"]')
    .first()
    .getAttribute("href");
  const rating = (
    await page
      .locator('a[href*="/ratings/"][href$="/edit"]')
      .getAttribute("href")
  ).replace("/edit", "");
  await page.locator(".list-menu > summary").click();
  await page
    .getByRole("button", { name: "Add to Wishlist", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Remove from Wishlist", exact: true }),
  ).toBeVisible();
  await page.goto(list);
  const shared = await page
    .getByRole("link", { name: "Open shared wine list" })
    .getAttribute("href");
  const entry = `/cellar/${drink.split("/").at(-2)}`;
  const wishlistEntry = `/wishlist/${id}`;
  const paths = [
    "/",
    "/settings",
    "/~test",
    "/~test/cellar",
    "/wines",
    "/wineries",
    "/~test/ratings",
    "/~test/wishlist",
    "/~test/lists",
    "/wines/new",
    "/wineries/new",
    "/~test/lists/new",
    wine,
    `${wine}/edit`,
    winery,
    `/wineries/${winery.split("/")[2]}/edit`,
    `${wine}/cellar/new`,
    drink.replace("/drink", "/edit"),
    drink,
    entry,
    wishlistEntry,
    `${wine}/ratings/new`,
    `${rating}/edit`,
    rating,
    list,
    `${list}/edit`,
    `${list}/print`,
    shared,
  ];
  for (const path of paths) {
    expect((await page.goto(path)).status(), path).toBe(200);
    if (path === "/" || path === "/~test") {
      await expect(page.locator("main details")).toHaveCount(0);
      await expect(page.locator(".rating-insights > hr")).toBeVisible();
      expect(await page.locator(".collection-highlights").evaluate(
        element => element.previousElementSibling.tagName,
      )).toBe("HR");
      await expect(
        page.getByRole("heading", { name: "Rating insights" }),
      ).toBeVisible();
      await expect(
        page.getByRole("heading", { name: "Cellar highlights" }),
      ).toBeVisible();
      await expect(
        page.getByRole("heading", { name: "Top rated" }),
      ).toBeVisible();
      await expect(page.locator(".rating-insights a").first()).toBeVisible();
    }
    if ([wine, entry, wishlistEntry, rating].includes(path)) {
      await expect(page.locator(".detail-content")).toHaveCSS(
        "background-color",
        "rgba(0, 0, 0, 0)",
      );
      await expect(page.locator(".detail-content")).toHaveCSS(
        "border-top-width",
        "0px",
      );
      await expect(page.locator(".detail-content")).toHaveCSS(
        "padding-left",
        "0px",
      );
    }
    for (const width of [320, 375, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 812 });
      await noOverflow(page);
    }
    await page.setViewportSize({ width: 375, height: 812 });
    await accessible(page);
  }
  await page.goto("/~test/cellar");
  await page.getByRole("searchbox").fill(name);
  await expect(page.locator("tbody tr:visible")).toHaveCount(1);
  await expect(
    page.locator('tbody tr:visible [data-label="Bottles"]'),
  ).toHaveText("3");
});

test("modal keyboard, history, deep links and short viewports", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await page.goto(wine);
  await open(page, "Add to cellar");
  await expect(page.locator(".site-main")).toHaveAttribute("inert", "");
  await expect(page.locator(".overlay-panel")).toHaveCSS(
    "background-color",
    "rgb(255, 255, 255)",
  );
  await expect(page.locator(".form-card")).toHaveCSS(
    "background-color",
    "rgb(255, 255, 255)",
  );
  await page.setViewportSize({ width: 375, height: 480 });
  await noOverflow(page);
  await accessible(page);
  await page.keyboard.press("Shift+Tab");
  await expect(
    page.getByRole("button", { name: "Add to Cellar", exact: true }),
  ).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(
    page.getByRole("button", { name: "Close dialog" }),
  ).toBeFocused();
  await page.keyboard.press("Escape");
  await saved(page, wine);
  await expect(
    page.getByRole("link", { name: "Add to cellar", exact: true }),
  ).toBeFocused();
  await open(page, "Add to cellar");
  await page.goBack();
  await saved(page, wine);
  await page.goForward();
  await expect(page).toHaveURL(new RegExp("/cellar/new$"));
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Add to Cellar", exact: true }),
  ).toBeVisible();
  await page.reload();
  await expect(page.getByRole("dialog")).toHaveCount(0);
});

test("add, edit, drink, rate and delete use correct enhanced requests", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  const posts = [];
  page.on("request", (r) => {
    if (r.method() === "POST") posts.push(new URL(r.url()).pathname);
  });
  await page.goto(wine);
  await open(page, "Add to cellar");
  await page
    .getByRole("combobox", { name: "Vintage", exact: true })
    .selectOption("2023");
  await page.getByRole("spinbutton", { name: "Quantity" }).fill("3");
  await page.getByLabel("Price per bottle", { exact: false }).fill("18.75");
  await page.getByLabel("Date", { exact: false }).fill("2026-09-05");
  await page
    .getByRole("button", { name: "Add to Cellar", exact: true })
    .click();
  await saved(page, wine);
  const edit = page.locator('a[href*="/cellar/"][href$="/edit"]').first();
  const purchaseEdit = await edit.getAttribute("href");
  await edit.click();
  await page.getByRole("spinbutton", { name: "Quantity" }).fill("4");
  await page.getByRole("button", { name: "Update Entry" }).click();
  await saved(page, wine);
  await open(page, "Drink");
  await page.getByLabel("Rate this bottle").check();
  await page.getByRole("button", { name: "Drink", exact: true }).click();
  await expect(page).toHaveURL(new RegExp("/ratings/new$"));
  await page.getByRole("spinbutton", { name: "Rating" }).fill("4.2");
  await page.getByLabel("Tasting Notes").fill("Citrus, with a long finish.");
  await page.getByRole("button", { name: "Save Rating" }).click();
  await saved(page, wine);
  await page.locator('a[href*="/ratings/"][href$="/edit"]').click();
  await page.getByRole("spinbutton", { name: "Rating" }).fill("4.4");
  await page.getByRole("button", { name: "Update Rating" }).click();
  await saved(page, wine);
  await page.locator('a[href*="/ratings/"][href$="/edit"]').click();
  page.once("dialog", (d) => d.dismiss());
  await page.getByRole("button", { name: "Delete this rating" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  expect(posts).toHaveLength(5);
  page.once("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Delete this rating" }).click();
  await saved(page, wine);
  expect(posts.at(-1)).toMatch(/\/ratings\/[^/]+\/delete$/);
  await page
    .locator(`a[href*="/cellar/"][href$="/edit"]:not([href="${purchaseEdit}"])`)
    .click();
  await expect(page.getByRole("spinbutton", { name: "Quantity" })).toHaveValue(
    "-1",
  );
  await expect(
    page.getByRole("spinbutton", { name: "Quantity" }),
  ).toHaveAttribute("max", "-1");
  await page.getByRole("button", { name: "Update Entry" }).click();
  await saved(page, wine);
  await page.locator(`a[href="${purchaseEdit}"]`).click();
  page.once("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Delete this entry" }).click();
  await saved(page, wine);
  expect(posts).toHaveLength(8);
  await expect(drinkLink(page)).toHaveCount(0);
});

test("cancel rating after drinking does not reopen a stale drink form", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await stock(request, wine, "1");
  await page.goto(wine);
  await open(page, "Drink");
  await page.getByLabel("Rate this bottle").check();
  await page.getByRole("button", { name: "Drink", exact: true }).click();
  await expect(page.getByRole("button", { name: "Save Rating" })).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();
  await saved(page, wine);
  await expect(drinkLink(page)).toHaveCount(0);
});

test("422 validation keeps values and focuses the error", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await page.goto(wine);
  await open(page, "Add to cellar");
  await page.getByLabel("Notes", { exact: true }).fill("Keep these notes <&>");
  await page.getByRole("spinbutton", { name: "Quantity" }).fill("0");
  await page.locator("#overlay form").evaluate((form) => {
    form.noValidate = true;
  });
  const response = page.waitForResponse((r) => r.request().method() === "POST");
  await page
    .getByRole("button", { name: "Add to Cellar", exact: true })
    .click();
  expect((await response).status()).toBe(422);
  await expect(page.locator(".form-error")).toBeFocused();
  const quantity = page.getByRole("spinbutton", { name: "Quantity" });
  await expect(quantity).toHaveAttribute("aria-invalid", "true");
  await expect(quantity).toHaveAttribute("aria-describedby", "validation-quantity");
  await expect(quantity).toHaveAccessibleDescription("Quantity must be at least 1");
  await expect(page.getByLabel("Notes", { exact: true })).not.toHaveAttribute("aria-invalid");
  await expect(page.getByLabel("Notes", { exact: true })).toHaveValue(
    "Keep these notes <&>",
  );
  await expect(page.getByRole("spinbutton", { name: "Quantity" })).toHaveValue(
    "0",
  );
  await expect(page.getByRole("combobox", { name: "Vintage" })).toHaveValue(
    "2023",
  );
  await page.getByRole("spinbutton", { name: "Quantity" }).fill("1");
  await page
    .getByRole("button", { name: "Add to Cellar", exact: true })
    .click();
  await saved(page, wine);
});

test("HTTP and network failures retain the form and re-enable retry", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await page.goto(wine);
  await open(page, "Add to cellar");
  await page.getByLabel("Notes", { exact: true }).fill("Do not lose this");
  for (const status of [403, 500, 0]) {
    await page.route(`**${wine}/cellar/new`, (route) =>
      status
        ? route.fulfill({ status, body: "Failed" })
        : route.abort("failed"),
    );
    await page
      .getByRole("button", { name: "Add to Cellar", exact: true })
      .click();
    await expect(page.locator(".request-error")).toBeVisible();
    await expect(page.getByLabel("Notes", { exact: true })).toHaveValue(
      "Do not lose this",
    );
    await expect(
      page.getByRole("button", { name: "Add to Cellar", exact: true }),
    ).toBeEnabled();
    await page.unroute(`**${wine}/cellar/new`);
  }
});

test("a pending mutation cannot be double-submitted or closed", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await page.goto(wine);
  await open(page, "Add to cellar");
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  let count = 0;
  await page.route(`**${wine}/cellar/new`, async (route) => {
    count++;
    await gate;
    await route.continue();
  });
  const button = page.getByRole("button", {
    name: "Add to Cellar",
    exact: true,
  });
  await button.click();
  await expect(button).toBeDisabled();
  await page.locator("#overlay form").evaluate((form) => form.requestSubmit());
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toBeVisible();
  release();
  await saved(page, wine);
  expect(count).toBe(1);
});

test("list create, edit, membership, share, remove and print", async ({
  page,
  request,
}) => {
  const { wine, name } = await seed(request);
  await page.goto("/~test/lists/new");
  await page.getByLabel("Name", { exact: true }).fill(`Dinner ${Date.now()}`);
  await page.getByRole("button", { name: "Create List" }).click();
  await expect(page).toHaveURL(/\/lists\/[^/]+$/);
  const list = new URL(page.url()).pathname;
  const listName = await page.getByRole("heading", { level: 1 }).textContent();
  await page.getByRole("link", { name: "Edit", exact: true }).click();
  await page.getByLabel("Description").fill("Bring something to share");
  await page.getByRole("button", { name: "Update", exact: true }).click();
  await expect(page.getByText("Bring something to share")).toBeVisible();
  await page.goto(wine);
  await page.locator(".list-menu > summary").click();
  await page
    .getByRole("button", { name: `Add to ${listName}`, exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: `Remove from ${listName}`, exact: true }),
  ).toBeVisible();
  await page.goto(list);
  await expect(page.getByRole("link", { name, exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Share", exact: true }).click();
  const shared = await page
    .getByRole("link", { name: "Open shared wine list" })
    .getAttribute("href");
  expect((await request.get(shared)).status()).toBe(200);
  await page.getByRole("link", { name, exact: true }).click();
  await expect(page).toHaveURL(`http://127.0.0.1:4101${wine}`);
  await page.goto(list);
  await page.getByRole("button", { name: `Remove ${name} from list`, exact: true }).click();
  await expect(page.getByRole("link", { name, exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Unshare", exact: true }).click();
  expect((await request.get(shared)).status()).toBe(404);
  await page.goto(`${list}/print`);
  await page.emulateMedia({ media: "print" });
  await noOverflow(page);
});

test("native wine and winery editing, export and boosted navigation", async ({
  page,
}) => {
  await page.goto("/wineries/new");
  await page
    .getByRole("textbox", { name: "Name", exact: true })
    .fill(`Estate ${Date.now()}`);
  await page.getByRole("button", { name: "Add Winery", exact: true }).click();
  await page.getByRole("link", { name: "Edit", exact: true }).click();
  await page
    .getByRole("textbox", { name: "Name", exact: true })
    .fill(`Updated Estate ${Date.now()}`);
  await page.getByRole("button", { name: "Update", exact: true }).click();
  await page.getByRole("link", { name: "Add Wine", exact: true }).click();
  await page
    .getByRole("textbox", { name: "Name", exact: true })
    .fill(`New Wine ${Date.now()}`);
  await page.getByLabel("Vintage", { exact: true }).fill("2023");
  await page.getByRole("button", { name: "Add Wine", exact: true }).click();
  await page.locator('main a[href$="/edit"]').first().click();
  await page.getByLabel("Personal Note").fill("Remember this producer");
  await page.getByRole("button", { name: "Update", exact: true }).click();
  await expect(page.getByText("Remember this producer")).toBeVisible();
  await page.locator('.site-nav a[href="/~test/cellar"]').click();
  await expect(page).toHaveURL(/\/~test\/cellar$/);
  await expect(page.locator('.site-nav a[aria-current="page"]')).toHaveText(
    "Cellar",
  );
  const download = page.waitForEvent("download");
  await page.getByRole("link", { name: /Export/ }).click();
  expect((await download).suggestedFilename()).toMatch(/\.csv$/);
});

test("native forms and uploads work without JavaScript", async ({
  browser,
  request,
}) => {
  const { wine } = await seed(request);
  const context = await browser.newContext({
    javaScriptEnabled: false,
    extraHTTPHeaders: { "x-test-user": "test" },
    viewport: { width: 375, height: 812 },
    baseURL: "http://127.0.0.1:4101",
  });
  const page = await context.newPage();
  await page.goto(wine);
  await page.getByRole("link", { name: "Add to cellar", exact: true }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await page
    .getByRole("combobox", { name: "Vintage", exact: true })
    .selectOption("");
  await page.getByLabel("Date", { exact: false }).fill("2026-09-05");
  await page
    .getByRole("button", { name: "Add to Cellar", exact: true })
    .click();
  await saved(page, wine);
  await drinkLink(page).click();
  await page.getByLabel("Date", { exact: false }).fill("2026-09-05");
  await page.getByLabel("Rate this bottle").check();
  await page.getByRole("button", { name: "Drink", exact: true }).click();
  await expect(page).toHaveURL(/ratings\/new\?rated_at=2026-09-05$/);
  await page.getByRole("spinbutton", { name: "Rating" }).fill("4.1");
  await page.getByRole("button", { name: "Save Rating" }).click();
  await saved(page, wine);
  await page.locator(".list-menu > summary").click();
  await page
    .getByRole("button", { name: "Add to Wishlist", exact: true })
    .click();
  await saved(page, wine);
  await page.locator(".list-menu > summary").click();
  await expect(
    page.getByRole("button", { name: "Remove from Wishlist", exact: true }),
  ).toBeVisible();
  await page.goto(`${wine}/edit`);
  await page.getByLabel("Label Photo").setInputFiles({
    name: "label.png",
    mimeType: "image/png",
    buffer: Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNoYFD4DwADRAGgxbo2YQAAAABJRU5ErkJggg==",
      "base64",
    ),
  });
  await page.getByRole("button", { name: "Update", exact: true }).click();
  await expect(page).toHaveURL(
    `http://127.0.0.1:4101${wine.split("/").slice(0, 3).join("/")}`,
  );
  await page.setViewportSize({ width: 768, height: 812 });
  const image = page.locator("main img").first();
  await expect(image).toBeVisible();
  expect(
    await image.evaluate((element) => element.naturalWidth),
  ).toBeGreaterThan(0);
  await context.close();
});

test("deep-linked form errors keep numeric values and allow retry", async ({
  page,
  request,
}) => {
  const { wine } = await seed(request);
  await page.goto(`${wine}/ratings/new`);
  const rating = page.getByRole("spinbutton", { name: "Rating" });
  await rating.fill("6");
  await page.getByLabel("Tasting Notes").fill("Keep this precise score");
  await page.locator(".form-card form").evaluate((form) => {
    form.noValidate = true;
  });
  await page.getByRole("button", { name: "Save Rating" }).click();
  await expect(page.locator(".form-error")).toBeFocused();
  await expect(rating).toHaveValue("6");
  await expect(page.getByLabel("Tasting Notes")).toHaveValue(
    "Keep this precise score",
  );
  await rating.fill("4.3");
  await page.route(`**${wine}/ratings/new`, (route) =>
    route.fulfill({ status: 500, body: "Failed" }),
  );
  await page.getByRole("button", { name: "Save Rating" }).click();
  await expect(page.locator(".request-error")).toBeFocused();
  await expect(rating).toHaveValue("4.3");
  await page.unroute(`**${wine}/ratings/new`);
  await page.getByRole("button", { name: "Save Rating" }).click();
  await saved(page, wine);
});

test("removed import screens have no navigation and return 404", async ({
  page,
  request,
}) => {
  await page.goto("/wines");
  await expect(page.getByRole("link", { name: /Import/ })).toHaveCount(0);
  const { wine } = await seed(request);
  for (const path of ["/~test/import", "/wines/import/vivino", `${wine}/sync`]) {
    expect((await request.get(path)).status()).toBe(404);
    expect((await request.post(path)).status()).toBe(404);
  }
});
