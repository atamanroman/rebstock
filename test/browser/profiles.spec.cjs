const { test, expect } = require("@playwright/test");

// A real, deliberately non-square 2×1 PNG. The public presentation must be square.
const picture = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVR4nGMoNHcNyvAEAAbjAfGhhdpAAAAAAElFTkSuQmCC",
  "base64",
);
const upload = { name: "portrait.png", mimeType: "image/png", buffer: picture };

async function expectSquare(image) {
  await expect(image).toBeVisible();
  expect(await image.evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true);
  const box = await image.boundingBox();
  expect(box.width).toBe(96);
  expect(box.height).toBe(96);
  expect(await image.evaluate(img => getComputedStyle(img).borderRadius)).toBe("0px");
}

async function expectAccessible(page) {
  await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
  const violations = await page.evaluate(async () => (await axe.run({
    runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] },
  })).violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.failureSummary) })));
  expect(violations).toEqual([]);
}

test("native profile settings, square pictures and logo fallback stay off home", async ({ browser, request }, testInfo) => {
  const username = `profile-${testInfo.project.name}`;
  const headers = { "x-test-user": username };
  // Populate the collection so / exercises the regular dashboard, not just the welcome page.
  const created = await request.post("/wines", {
    headers,
    form: { name: `Profile wine ${testInfo.project.name}`, winery: "Profile winery", wine_type: "red" },
  });
  expect(created.ok()).toBe(true);
  const context = await browser.newContext({
    javaScriptEnabled: false,
    extraHTTPHeaders: headers,
    baseURL: "http://127.0.0.1:4101",
    viewport: { width: 375, height: 812 },
  });
  try {
    const page = await context.newPage();
    await page.goto(`/~${username}`);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(username);
    await expect(page.locator("main .profile-picture")).toHaveAttribute("src", "/static/grapevine.svg");
    await expectSquare(page.locator("main .profile-picture"));
    await page.locator(".user-menu > summary").click();
    await expect(page.getByRole("link", { name: "Settings", exact: true })).toHaveAttribute("href", "/settings");
    await expect(page.getByRole("link", { name: "Your profile", exact: true })).toHaveAttribute("href", `/~${username}`);
    await page.getByRole("link", { name: "Settings", exact: true }).click();
    await expect(page).toHaveURL(/\/settings$/);
    await expect(page.getByRole("textbox", { name: "Name", exact: true })).toHaveValue(username);
    await page.getByRole("textbox", { name: "Name", exact: true }).fill("Alex Wine");
    await page.getByLabel("Picture", { exact: true }).setInputFiles(upload);
    await page.getByRole("button", { name: "Save profile" }).click();
    await expect(page).toHaveURL(/\/settings\?saved=1$/);
    await expect(page.getByRole("status")).toHaveText("Profile saved.");
    const image = page.locator("main .profile-picture");
    const src = await image.getAttribute("src");
    expect(src).toMatch(/^\/images\/profiles\/[0-9A-Z]+\.png$/);
    await expectSquare(image);
    expect((await request.get(src)).headers()["content-type"]).toContain("image/png");
    await page.getByRole("link", { name: "View your public profile" }).click();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Alex Wine");
    await expect(page.locator("main .profile-picture")).toHaveAttribute("src", src);
    await expectSquare(page.locator("main .profile-picture"));
    expect(await page.locator("main .profile-picture").evaluate(img => getComputedStyle(img).objectFit)).toBe("cover");
    const visitor = await request.get(`/~${username}`, { headers: { "x-test-user": "profile-visitor" } });
    expect(visitor.status()).toBe(200);
    const publicHtml = await visitor.text();
    expect(publicHtml).toContain("<h1>Alex Wine</h1>");
    expect(publicHtml).toContain(src);
    expect(publicHtml).not.toContain('name="display_name"');
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Your collection");
    await expect(page.locator("main .profile-picture")).toHaveCount(0);
    await page.goto("/settings");
    await page.getByLabel("Remove picture").check();
    await page.getByRole("button", { name: "Save profile" }).click();
    await expect(page.getByRole("status")).toHaveText("Profile saved.");
    await expect(page.locator("main .profile-picture")).toHaveAttribute("src", "/static/grapevine.svg");
    expect((await request.get(src)).status()).toBe(404);
    await page.goto(`/~${username}`);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Alex Wine");
    await expect(page.locator("main .profile-picture")).toHaveAttribute("src", "/static/grapevine.svg");
    await expectSquare(page.locator("main .profile-picture"));
  } finally {
    await context.close();
  }
});

test("invalid pictures preserve profiles and replacement uses safe content types", async ({ page, request }, testInfo) => {
  const username = `picture-errors-${testInfo.project.name}`;
  const headers = { "x-test-user": username };
  await page.setExtraHTTPHeaders(headers);
  await page.goto("/settings");
  const saved = await request.post("/settings", {
    headers,
    multipart: { display_name: "Original name", picture: { name: "untrusted.svg", mimeType: "image/svg+xml", buffer: picture } },
    maxRedirects: 0,
  });
  expect(saved.status()).toBe(303);
  await page.goto("/settings");
  const oldSrc = await page.locator("main .profile-picture").getAttribute("src");
  expect(oldSrc).toMatch(/\.png$/);
  await expectAccessible(page);
  await page.getByRole("textbox", { name: "Name", exact: true }).fill("Unsaved name");
  await page.getByLabel("Picture", { exact: true }).setInputFiles({
    name: "not-really-a-photo.png", mimeType: "image/png", buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'),
  });
  await page.getByRole("button", { name: "Save profile" }).click();
  await expect(page.getByRole("alert")).toContainText("Choose a PNG, JPEG or WebP picture.");
  await expect(page.getByRole("textbox", { name: "Name", exact: true })).toHaveValue("Unsaved name");
  await expect(page.getByLabel("Picture", { exact: true })).toHaveAttribute("aria-invalid", "true");
  await expect(page.getByLabel("Picture", { exact: true })).toHaveAttribute("aria-describedby", /profile-picture-help.*validation-picture/);
  await expect(page.locator("main .profile-picture")).toHaveAttribute("src", oldSrc);
  await expectAccessible(page);
  const tooLarge = Buffer.alloc(2_000_001);
  picture.copy(tooLarge);
  await page.getByLabel("Picture", { exact: true }).setInputFiles({ ...upload, buffer: tooLarge });
  await page.getByRole("button", { name: "Save profile" }).click();
  await expect(page.getByRole("alert")).toContainText("no larger than 2 MB");
  await page.getByLabel("Picture", { exact: true }).setInputFiles(upload);
  await page.getByLabel("Remove picture").check();
  await page.getByRole("button", { name: "Save profile" }).click();
  await expect(page.getByRole("alert")).toContainText("not both");
  await expect(page.getByLabel("Remove picture")).toBeChecked();
  const unchanged = await request.get(`/~${username}`, { headers });
  expect(await unchanged.text()).toContain("<h1>Original name</h1>");
  await expect(page.locator("main .profile-picture")).toHaveAttribute("src", oldSrc);
  await page.getByLabel("Remove picture").uncheck();
  await page.getByLabel("Picture", { exact: true }).setInputFiles(upload);
  await page.getByRole("button", { name: "Save profile" }).click();
  await expect(page.getByRole("status")).toHaveText("Profile saved.");
  const newSrc = await page.locator("main .profile-picture").getAttribute("src");
  expect(newSrc).not.toBe(oldSrc);
  expect((await request.get(oldSrc)).status()).toBe(404);
  expect((await request.get(newSrc)).headers()["content-type"]).toContain("image/png");
  await page.goto(`/~${username}`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Unsaved name");
  await expectAccessible(page);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  const longName = "A".repeat(100);
  expect((await request.post("/settings", { headers, form: { display_name: longName }, maxRedirects: 0 })).status()).toBe(303);
  await page.goto(`/~${username}`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(longName);
  for (const width of [320, 375, 768, 1440]) {
    await page.setViewportSize({ width, height: 812 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  await page.getByRole("link", { name: "Home", exact: true }).click();
  await expect(page).toHaveURL("http://127.0.0.1:4101/");
  await expect(page.locator("main .profile-picture")).toHaveCount(0);
});
