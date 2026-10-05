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
