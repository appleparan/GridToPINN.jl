import { expect, test } from '@playwright/test';
import { BASE, PREFIX, SHOTS, watch } from './helpers';

test('home shows nine step cards, three available', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/`);
	await expect(page.getByRole('heading', { level: 1 })).toContainText('GridToPINN');
	const cards = page.getByTestId('step-card');
	await expect(cards).toHaveCount(9);
	await expect(page.locator('[data-testid=step-card][data-available=true]')).toHaveCount(3);
	await expect(cards.nth(0)).toContainText('미분과 Newton법');
	await expect(cards.nth(0)).toContainText('DRS를 열면');
	await expect(cards.nth(8)).toContainText('준비 중');
	await expect(page.getByTestId('verify-link')).toHaveAttribute('href', `${BASE}/verify`);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}home.png`, fullPage: true });
	expect(w.problems).toEqual([]);
});

test('card opens the step page; sidebar navigates; unavailable steps say so', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/`);
	await page.locator('[data-testid=step-card][data-step="3"]').click();
	await expect(page).toHaveURL(new RegExp(`${BASE}/step/3/?$`));
	await expect(page.getByTestId('step-title')).toContainText('확산');
	await expect(page.getByTestId('step-question')).toContainText('물과 꿀');
	await expect(page.getByTestId('nav-step')).toHaveCount(9);
	await expect(page.locator('[data-testid=nav-step][aria-current=page]')).toHaveAttribute('data-step', '3');
	await page.getByTestId('prev-step').click();
	await expect(page.getByTestId('step-title')).toContainText('시간 전진');
	await page.locator('[data-testid=nav-step][data-step="5"]').click();
	await expect(page.getByTestId('step-title')).toContainText('Poisson');
	await expect(page.getByTestId('coming-soon')).toBeVisible();
	expect(w.problems).toEqual([]);
});

test('dark mode toggles and persists across reload', async ({ page }) => {
	await page.emulateMedia({ colorScheme: 'light' });
	await page.goto(`${BASE}/step/1`);
	const html = page.locator('html');
	await expect(html).not.toHaveClass(/dark/);
	await page.getByTestId('theme-toggle').click();
	await expect(html).toHaveClass(/dark/);
	await page.reload();
	await expect(html).toHaveClass(/dark/);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}step1-dark-shell.png`, fullPage: true });
});

test('system dark preference is the default', async ({ page }) => {
	await page.emulateMedia({ colorScheme: 'dark' });
	await page.goto(`${BASE}/`);
	await expect(page.locator('html')).toHaveClass(/dark/);
});

test('narrow viewport: sidebar collapses into a drawer and the page does not scroll sideways', async ({ page }) => {
	await page.setViewportSize({ width: 390, height: 800 });
	await page.goto(`${BASE}/step/2`);
	await expect(page.getByTestId('step-title')).toBeVisible();
	expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
	await page.getByRole('button', { name: '단계 목록' }).click();
	await expect(page.locator('[data-testid=nav-step][data-step="1"]')).toBeVisible();
});
