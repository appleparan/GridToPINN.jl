import { expect, test, type Page } from '@playwright/test';
import { BASE, PREFIX, SHOTS, watch } from './helpers';

const num = async (page: Page, key: string) => Number(await page.getByTestId(`readout-${key}`).getAttribute('data-value'));

test('step 1 computes on load, without a click', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	expect(await num(page, 'v-closed')).toBeCloseTo(323.5, 1);
	expect(await num(page, 'v-open')).toBeCloseTo(336.5, 1);
	expect(await num(page, 'gain')).toBeCloseTo(13.0, 1);
	expect(Number(await page.getByTestId('plot').getAttribute('data-points'))).toBeGreaterThan(2);
	await expect(page.getByTestId('plot').locator('canvas')).toBeVisible();
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step1.png`, fullPage: true });
	expect(w.problems).toEqual([]);
});

test('typing a parameter recomputes; keyboard moves the slider', async ({ page }) => {
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	const before = await num(page, 'v-open');
	const input = page.getByTestId('param-input-Cd_open');
	await input.fill('0.5');
	await input.press('Enter');
	await expect.poll(() => num(page, 'v-open')).toBeGreaterThan(before + 10);
	const p0 = Number(await page.getByTestId('param-P').getAttribute('data-value'));
	await page.getByTestId('param-P').getByRole('slider').focus();
	await page.keyboard.press('ArrowRight');
	await expect.poll(async () => Number(await page.getByTestId('param-P').getAttribute('data-value'))).toBeGreaterThan(p0);
});

test('a typed value is committed once, without 4-digit rounding', async ({ page }) => {
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	const input = page.getByTestId('param-input-P');
	await input.fill('123456');
	await input.press('Enter');
	await expect(page.getByTestId('param-P')).toHaveAttribute('data-value', '123456');
	await page.waitForTimeout(300);
	await expect(page.getByTestId('param-P')).toHaveAttribute('data-value', '123456');
});

test('bad input is clamped or ignored, never sent as NaN', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	const input = page.getByTestId('param-input-Cd_open');
	const wrap = page.getByTestId('param-Cd_open');
	await input.fill('abc'); await input.press('Enter');
	await expect(wrap).toHaveAttribute('data-value', '0.8');
	await input.fill(''); await input.press('Enter');
	await expect(wrap).toHaveAttribute('data-value', '0.8');
	await input.fill('999'); await input.press('Enter');
	await expect(wrap).toHaveAttribute('data-value', '3');
	await expect(page.getByTestId('verdict')).not.toHaveAttribute('data-verdict', 'diverged');
	expect(w.problems).toEqual([]);
});

test('switching the alternative swaps the code and the result', async ({ page }) => {
	await page.goto(`${BASE}/step/1`);
	const code = page.getByTestId('code-panel');
	await expect(code).toHaveAttribute('data-key', 'hand', { timeout: 30_000 });
	const handText = await code.textContent();
	const handIters = await num(page, 'iterations');
	// a coarse step makes forward differences visibly worse than the hand derivative
	const h = page.getByTestId('param-input-h');
	await h.fill('10'); await h.press('Enter');
	await page.getByTestId('alt-option-forward').click();
	await expect(code).toHaveAttribute('data-key', 'forward');
	expect(await code.textContent()).not.toBe(handText);
	await expect(page.getByTestId('alt-derivative')).toHaveAttribute('data-value', 'forward');
	await expect.poll(() => num(page, 'iterations')).not.toBe(handIters);
	await page.getByTestId('alt-option-dual').click();
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass');
});

test('breaking it shows a diverged badge, not an error', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	const v0 = page.getByTestId('param-input-v0');
	await v0.fill('0'); await v0.press('Enter'); // f'(0) = 0 -> NaN
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'diverged');
	await expect(page.getByTestId('plot')).toBeVisible();
	await expect(page.getByTestId('load-error')).toHaveCount(0);
	expect(w.problems).toEqual([]);
});

test('Float32 changes the numbers; the plot survives a theme toggle', async ({ page }) => {
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	// rel-error is exactly 0 at the defaults in both precisions, so compare the closed-DRS speed itself
	const v64 = await num(page, 'v-closed');
	await page.getByTestId('precision-f32').click();
	await expect.poll(() => num(page, 'v-closed')).not.toBe(v64);
	await page.getByTestId('theme-toggle').click();
	await expect(page.locator('html')).toHaveClass(/dark/);
	await expect(page.getByTestId('plot').locator('canvas')).toBeVisible();
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step1-dark.png`, fullPage: true });
});

test('step 1 reveals the Newton iterates one by one, then is done', async ({ page }) => {
	await page.goto(`${BASE}/step/1`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await expect(page.getByTestId('play-status')).toHaveAttribute('data-status', 'playing');
	const iterations = await num(page, 'iterations');
	expect(await num(page, 'play-iteration')).toBeLessThan(iterations - 1);
	await expect(page.getByTestId('play-status')).toHaveAttribute('data-status', 'done', { timeout: 15_000 });
	expect(await num(page, 'play-iteration')).toBe(iterations - 1);
});
