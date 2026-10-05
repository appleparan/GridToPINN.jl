import { expect, test, type Page } from '@playwright/test';
import { BASE, PREFIX, SHOTS, watch } from './helpers';

const num = async (page: Page, key: string) => Number(await page.getByTestId(`readout-${key}`).getAttribute('data-value'));
const set = async (page: Page, name: string, text: string) => {
	const i = page.getByTestId(`param-input-${name}`);
	await i.fill(text); await i.press('Enter');
};

test('step 2 computes on load and reaches the step 1 top speed', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	expect(await num(page, 'target')).toBeCloseTo(336.5, 1);
	expect(Number(await page.getByTestId('plot').getAttribute('data-points'))).toBeGreaterThan(10);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step2.png`, fullPage: true });
	expect(w.problems).toEqual([]);
});

test('adaptive integrator takes smaller steps than its largest one', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await page.getByTestId('alt-option-adaptive').click();
	await expect(page.getByTestId('code-panel')).toHaveAttribute('data-key', 'adaptive');
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	expect(await num(page, 'dt-min')).toBeLessThan(await num(page, 'dt-max'));
});

test('changing mass changes the settling time; changing t_open moves nothing off screen', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	const s0 = await num(page, 'settling');
	await set(page, 'm', '1600');
	await expect.poll(() => num(page, 'settling')).toBeGreaterThan(s0);
	await set(page, 't_open', '40');
	await expect(page.getByTestId('plot').locator('canvas')).toBeVisible();
});

test('Euler past its stability limit goes bad without throwing', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/2`);
	await page.getByTestId('alt-option-euler').click();
	await set(page, 'Δt', '30'); // manifest doc: Euler stability limit is about 7 s
	await expect(page.getByTestId('verdict')).not.toHaveAttribute('data-verdict', 'pass');
	await expect(page.getByTestId('plot')).toBeVisible();
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step2-break.png`, fullPage: true });
	expect(w.problems).toEqual([]);
});

test('dragging does not recompute the muted curves every frame', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await set(page, 'Δt', '0.001');
	await expect(page.getByTestId('readout-steps')).toHaveAttribute('data-value', '80000', { timeout: 30_000 });
	await page.waitForTimeout(600);
	const runs = async () => Number(await page.getByTestId('experiment').getAttribute('data-muted-runs'));
	const before = await runs();
	await page.getByTestId('param-P').getByRole('slider').focus();
	for (let i = 0; i < 10; i++) await page.keyboard.press('ArrowRight');
	await page.waitForTimeout(800);
	expect(await runs() - before).toBeLessThanOrEqual(3);
	expect(await runs() - before).toBeGreaterThanOrEqual(1);
});

const playStatus = (page: Page) => page.getByTestId('play-status');

test('step 2 plays by itself while the verdict is already final', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await expect(playStatus(page)).toHaveAttribute('data-status', 'playing');
	const t1 = await num(page, 'play-time');
	await expect.poll(() => num(page, 'play-time')).toBeGreaterThan(t1);
	await expect(page.getByTestId('play-progress')).toHaveAttribute('aria-valuenow', /\d+/);
	await expect(playStatus(page)).toHaveAttribute('data-status', 'done', { timeout: 15_000 });
	expect(await num(page, 'play-time')).toBe(80);
	expect(await num(page, 'play-speed')).toBeCloseTo(await num(page, 'v-end'), 3);
	expect(w.problems).toEqual([]);
});

test('pause freezes the playback, play resumes, restart starts over', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(playStatus(page)).toHaveAttribute('data-status', 'playing', { timeout: 30_000 });
	await expect.poll(() => num(page, 'play-time')).toBeGreaterThan(5);
	await page.getByTestId('play-pause').click();
	await expect(playStatus(page)).toHaveAttribute('data-status', 'paused');
	const t = await num(page, 'play-time');
	await page.waitForTimeout(300);
	expect(await num(page, 'play-time')).toBe(t);
	await page.getByTestId('play-play').click();
	await expect.poll(() => num(page, 'play-time')).toBeGreaterThan(t);
	await expect.poll(() => num(page, 'play-time')).toBeGreaterThan(t + 2);
	await page.getByTestId('play-restart').click();
	await expect.poll(() => num(page, 'play-time')).toBeLessThan(t);
});

test('changing a parameter restarts the playback', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(playStatus(page)).toHaveAttribute('data-status', 'done', { timeout: 30_000 });
	expect(await num(page, 'play-time')).toBe(80);
	await set(page, 'm', '1600');
	await expect.poll(() => num(page, 'play-time')).toBeLessThan(80);
	await expect(playStatus(page)).toHaveAttribute('data-status', 'playing');
});

test('reduced motion: step 2 loads already finished', async ({ page }) => {
	await page.emulateMedia({ reducedMotion: 'reduce' });
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await expect(playStatus(page)).toHaveAttribute('data-status', 'done');
	expect(await num(page, 'play-time')).toBe(80);
});

test('the playback speed readout only shows steps the integrator computed', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await page.getByTestId('alt-option-euler').click();
	await set(page, 'Δt', '10'); // 80 s / 10 s = 8 steps = 9 samples
	await expect(page.getByTestId('readout-steps')).toHaveAttribute('data-value', '8', { timeout: 30_000 });
	await expect(playStatus(page)).toHaveAttribute('data-status', 'playing');
	const polled: string[] = await page.evaluate(async () => {
		const out: string[] = [];
		const el = document.querySelector('[data-testid="readout-play-speed"]')!;
		for (let i = 0; i < 80; i++) {
			out.push(el.getAttribute('data-value') ?? '');
			await new Promise((r) => setTimeout(r, 30));
		}
		return out;
	});
	const distinct = new Set(polled).size;
	const changes = polled.filter((v, i) => i > 0 && v !== polled[i - 1]).length;
	// an interpolated readout would change at nearly every poll and take dozens of values
	expect(distinct).toBeLessThanOrEqual(9);
	expect(changes).toBeLessThanOrEqual(8);
	expect(polled.length - changes).toBeGreaterThan(polled.length / 2); // values hold across consecutive polls
});

test('hovering the plot reads the values under the cursor', async ({ page }) => {
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await expect(playStatus(page)).toHaveAttribute('data-status', 'done', { timeout: 15_000 });
	const cursor = page.getByTestId('plot-cursor');
	await expect(cursor).not.toBeVisible();
	await page.getByTestId('plot').locator('.u-over').hover(); // uPlot's interaction overlay sits above the canvas
	await expect(cursor).toBeVisible();
	await expect(cursor).toContainText(/\d/);
	await expect(cursor).toContainText('km/h');
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step2-hover.png`, fullPage: true });
	await page.mouse.move(2, 2);
	await expect(cursor).not.toBeVisible();
});
