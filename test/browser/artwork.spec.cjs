const { test, expect } = require("@playwright/test");
const { seed, noOverflow, accessible } = require("./helpers.cjs");

// Assert the rendering contract, not the artist's path counts, colors or SVG classes.
test("all wine types have distinct, accessible bottle fallbacks", async ({ page, request }) => {
  const assets = new Set();
  for (const [type, label] of [
    ["red", "Red"], ["white", "White"], ["rose", "Rosé"], ["orange", "Orange"],
    ["sparkling", "Sparkling"], ["dessert", "Dessert"], ["sake", "Sake"], ["other", "Other"],
  ]) {
    const { wine } = await seed(request, type);
    await page.goto(wine);
    const name = type === "sake"
      ? "Sake flask illustration with 酒 (sake) on the label"
      : type === "sparkling"
        ? "Sparkling wine bottle illustration with a fully seated cork"
        : `${label} wine bottle illustration`;
    const placeholder = page.getByRole("img", { name, exact: true });
    await expect(placeholder).toBeVisible();
    const image = placeholder.locator("img");
    await expect(image).toHaveAttribute("src", `/static/bottles/${type}.svg`);
    await expect(image).toHaveAttribute("alt", "");
    await expect.poll(() => image.evaluate(element => element.complete && element.naturalWidth > 0)).toBe(true);

    const response = await request.get(`/static/bottles/${type}.svg`);
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("image/svg+xml");
    const source = await response.text();
    expect(await page.evaluate(svg => {
      const document = new DOMParser().parseFromString(svg, "image/svg+xml");
      return document.documentElement.localName === "svg" && !document.querySelector("parsererror");
    }, source)).toBe(true);
    assets.add(source);
    await noOverflow(page);
    await accessible(page);
  }
  expect(assets.size).toBe(8);
});
