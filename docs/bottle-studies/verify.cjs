const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium, webkit } = require('@playwright/test');

const directory = __dirname;
const data = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
assert.equal(data.baseline_commit, 'bf82e95');
assert.equal(data.count, 80);
assert.equal(data.candidates.length, 80);
assert.equal(data.types.length, 8);
assert.equal(new Set(data.candidates.map(candidate => candidate.id)).size, 80);
const assets = data.candidates.map(candidate => ({ ...candidate, svg: fs.readFileSync(path.join(directory, candidate.asset), 'utf8') }));
assert.equal(new Set(assets.map(candidate => candidate.svg)).size, 80, 'Every SVG must be original, not a duplicate');
for (const type of data.types) {
  assert.equal(assets.filter(candidate => candidate.type === type.id).length, 10);
}
for (const candidate of assets) {
  assert.equal(candidate.generation.isolated_session, true);
  assert.match(candidate.svg, /viewBox=['"]0 0 120 280['"]/);
  assert.doesNotMatch(candidate.svg, /<(?:script|text|image|foreignObject|filter|style)\b|\bon\w+\s*=|\b(?:href|xlink:href)\s*=/i, candidate.id);
  assert.ok(fs.existsSync(path.join(directory, 'briefs', candidate.type + '-' + String(candidate.number).padStart(2, '0') + '.txt')));
}

async function noOverflow(page) {
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Page must fit viewport');
}
async function accessible(page) {
  await page.addScriptTag({ path: require.resolve('axe-core/axe.min.js') });
  const violations = await page.evaluate(async () => (await axe.run({ runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } })).violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.target) })));
  assert.deepEqual(violations, []);
}
async function verify(name, engine) {
  const browser = await engine.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(pathToFileURL(path.join(directory, 'index.html')).href);
    assert.equal(await page.locator('.card').count(), 80);
    assert.equal(await page.locator('.cards').count(), 8);
    const xmlErrors = await page.evaluate(inputs => inputs.flatMap(({ id, svg }) => {
      const doc = new DOMParser().parseFromString(svg, 'image/svg+xml');
      return doc.querySelector('parsererror') ? [id] : [];
    }), assets.map(({ id, svg }) => ({ id, svg })));
    assert.deepEqual(xmlErrors, []);
    await page.locator('.art img').evaluateAll(images => images.forEach(image => { image.loading = 'eager'; }));
    await page.waitForFunction(() => [...document.querySelectorAll('.art img')].every(image => image.complete && image.naturalWidth > 0));
    await noOverflow(page);
    await accessible(page);
    for (const type of data.types) {
      await page.getByLabel('Show', { exact: true }).selectOption(type.id);
      assert.equal(await page.locator('main > section:visible').count(), 1);
      assert.equal(await page.locator('main > section:visible .card').count(), 10);
      if (name === 'chromium') {
        fs.mkdirSync(path.join(directory, 'previews'), { recursive: true });
        await page.locator('#' + type.id).screenshot({ path: path.join(directory, 'previews', type.id + '.png') });
      }
      const radio = page.getByRole('radio', { name: new RegExp('^Choose ' + type.id.toUpperCase() + '-03:') });
      await radio.check();
      assert.ok(await radio.isChecked());
    }
    await page.reload();
    assert.equal(await page.locator('input[type=radio]:checked').count(), 8, 'Picks must survive reload');
    await page.getByLabel('Show', { exact: true }).selectOption('sparkling');
    const trigger = page.getByRole('button', { name: /^Enlarge SPARKLING-01:/ });
    await trigger.click();
    assert.ok(await page.getByRole('dialog').isVisible());
    await accessible(page);
    await page.keyboard.press('Escape');
    assert.equal(await page.getByRole('dialog').count(), 0);
    assert.ok(await trigger.evaluate(element => element === document.activeElement));
    await page.getByLabel('Actual app size').check();
    const actualSize = await page.locator('#sparkling .art img').first().boundingBox();
    assert.equal(actualSize.width, 88);
    assert.equal(actualSize.height, 220);
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download selections', exact: true }).click();
    const download = await downloadPromise;
    const selection = JSON.parse(fs.readFileSync(await download.path(), 'utf8'));
    assert.equal(selection.selections.length, 8);
    for (const width of [320, 375, 768]) {
      await page.setViewportSize({ width, height: 900 });
      await noOverflow(page);
    }
    await accessible(page);
    await page.getByRole('button', { name: 'Clear selections', exact: true }).click();
    assert.equal(await page.locator('input[type=radio]:checked').count(), 0);
    assert.deepEqual(errors, []);
    await context.close();
    console.log(name + ': 80 SVGs rendered; picks, persistence, preview, export, mobile and axe passed');
  } finally { await browser.close(); }
}
(async () => {
  await verify('chromium', chromium);
  await verify('webkit', webkit);
})().catch(error => { console.error(error); process.exitCode = 1; });
