import { expect, test, type Page } from '@playwright/test';
import { BASE, PREFIX, SHOTS, watch } from './helpers';

const num = async (page: Page, key: string) => Number(await page.getByTestId(`readout-${key}`).getAttribute('data-value'));
const status = (page: Page) => page.getByTestId('run-status');

test('step 3 starts by itself in a Worker and animates to the end', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/3`);
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	const t1 = await num(page, 'time');
	await expect.poll(() => num(page, 'time')).toBeGreaterThan(t1); // intermediate frames arrive
	expect(page.workers().length).toBeGreaterThan(0);
	await expect(status(page)).toHaveAttribute('data-status', 'done', { timeout: 30_000 });
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass');
	expect(await num(page, 'stability')).toBeLessThan(0.5);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step3.png`, fullPage: true });
	for (const u of w.wasmUrls) expect(u.startsWith(`${BASE}/wasm/step`)).toBe(true);
	expect(w.problems).toEqual([]);
});

test('pause freezes time, play resumes, reset starts over', async ({ page }) => {
	await page.goto(`${BASE}/step/3`);
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	await page.getByTestId('run-pause').click();
	await expect(status(page)).toHaveAttribute('data-status', 'paused');
	const t = await num(page, 'time');
	await page.waitForTimeout(300);
	expect(await num(page, 'time')).toBe(t);
	await page.getByTestId('run-play').click();
	await expect.poll(() => num(page, 'time')).toBeGreaterThan(t);
	await expect(status(page)).toHaveAttribute('data-status', 'done', { timeout: 30_000 });
	const tEnd = await num(page, 'time');
	await page.getByTestId('run-reset').click();
	await expect.poll(() => num(page, 'time')).toBeLessThan(tEnd);
});

test('honey preset breaks Euler; Crank–Nicolson survives the same settings', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/3`);
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	await page.getByTestId('preset-ν-1').click(); // 꿀
	await expect(page.getByTestId('param-ν')).toHaveAttribute('data-value', '0.002');
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'diverged', { timeout: 30_000 });
	await expect(status(page)).toHaveAttribute('data-status', 'diverged');
	expect(await num(page, 'stability')).toBeGreaterThan(0.5);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step3-break.png`, fullPage: true });
	await page.getByTestId('alt-option-cn').click();
	await expect(page.getByTestId('code-panel')).toHaveAttribute('data-key', 'cn');
	await expect(status(page)).toHaveAttribute('data-status', 'done', { timeout: 30_000 });
	await expect(page.getByTestId('verdict')).not.toHaveAttribute('data-verdict', 'diverged');
	expect(w.problems).toEqual([]);
});

test('rapid changes and leaving mid-run cause no errors', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/step/3`);
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	const slider = page.getByTestId('param-N').getByRole('slider');
	await slider.focus();
	for (let i = 0; i < 15; i++) await page.keyboard.press('ArrowRight');
	await page.getByTestId('precision-f32').click();
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	await page.locator('[data-testid=nav-step][data-step="1"]').click();
	await expect(page.getByTestId('verdict')).toHaveAttribute('data-verdict', 'pass', { timeout: 30_000 });
	await page.locator('[data-testid=nav-step][data-step="3"]').click();
	await expect(status(page)).toHaveAttribute('data-status', 'running', { timeout: 30_000 });
	expect(w.problems).toEqual([]);
});
