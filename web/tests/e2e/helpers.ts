import type { Page } from '@playwright/test';

export const BASE = process.env.BASE_PATH ?? '';
export const PREFIX = BASE ? 'sub-' : '';
export const SHOTS = 'test-results/screenshots';

/** 콘솔 오류, 페이지 예외, 실패/4xx/5xx 요청을 모아 둔다. 시험 끝에서 비어 있어야 한다. */
export function watch(page: Page) {
	const problems: string[] = [];
	const wasmUrls: string[] = [];
	page.on('console', (m) => m.type() === 'error' && problems.push(`console.error: ${m.text()}`));
	page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
	page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()} ${r.failure()?.errorText}`));
	page.on('response', (r) => {
		if (r.status() >= 400) problems.push(`HTTP ${r.status()}: ${r.url()}`);
		if (r.url().endsWith('.wasm')) wasmUrls.push(new URL(r.url()).pathname);
	});
	return { problems, wasmUrls };
}

/** canvas에서 흰 배경이 아닌 픽셀 수와, 색이 있는(회색이 아닌) 픽셀 수 */
export const pixels = (page: Page, testid: string) =>
	page.getByTestId(testid).evaluate((c: HTMLCanvasElement) => {
		const d = c.getContext('2d')!.getImageData(0, 0, c.width, c.height).data;
		let nonBg = 0, colored = 0;
		for (let i = 0; i < d.length; i += 4) {
			if (d[i] !== 255 || d[i + 1] !== 255 || d[i + 2] !== 255) nonBg++;
			if (d[i] !== d[i + 1] || d[i + 1] !== d[i + 2]) colored++;
		}
		return { nonBg, colored };
	});
