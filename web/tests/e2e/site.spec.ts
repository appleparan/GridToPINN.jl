import { expect, test, type Page } from '@playwright/test';

const BASE = process.env.BASE_PATH ?? '';
const PREFIX = BASE ? 'sub-' : '';
const SHOTS = 'test-results/screenshots';

/** 콘솔 오류, 페이지 예외, 실패/4xx/5xx 요청을 모아 둔다. 시험 끝에서 비어 있어야 한다. */
function watch(page: Page) {
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
const pixels = (page: Page, testid: string) =>
	page.getByTestId(testid).evaluate((c: HTMLCanvasElement) => {
		const d = c.getContext('2d')!.getImageData(0, 0, c.width, c.height).data;
		let nonBg = 0, colored = 0;
		for (let i = 0; i < d.length; i += 4) {
			if (d[i] !== 255 || d[i + 1] !== 255 || d[i + 2] !== 255) nonBg++;
			if (d[i] !== d[i + 1] || d[i + 1] !== d[i + 2]) colored++;
		}
		return { nonBg, colored };
	});

test('home page renders the step list', async ({ page }) => {
	const w = watch(page);
	await page.goto(`${BASE}/`);
	await expect(page.getByRole('heading', { level: 1 })).toContainText('GridToPINN');
	const rows = page.getByTestId('step-row');
	await expect(rows).toHaveCount(3);
	// 제목, 매니페스트에서 읽은 질문, wasm 크기
	const expected = [['미분과 Newton법', 'DRS를 열면'], ['시간 전진', '도달하는 데'], ['확산', '물과 꿀']];
	for (const [i, [title, question]] of expected.entries()) {
		await expect(rows.nth(i)).toContainText(title);
		await expect(rows.nth(i)).toContainText(question);
		await expect(rows.nth(i)).toContainText(/\d+\.\d KiB/);
	}
	await expect(page.getByTestId('verify-link')).toHaveAttribute('href', `${BASE}/verify`);
	await page.screenshot({ path: `${SHOTS}/${PREFIX}home.png`, fullPage: true });
	await expect(page.getByTestId('error')).toHaveCount(0);
	expect(w.problems).toEqual([]);
});

test('verify page: parity, alternatives, plots, worker frames', async ({ page }) => {
	const w = watch(page);
	await page.addInitScript(() => {
		// 3단계 프레임 카운터가 거친 값을 모두 기록한다 (중간 프레임이 실제로 도착했는지 확인용)
		(window as any).__frames = [];
		document.addEventListener('DOMContentLoaded', () => {
			new MutationObserver(() => {
				const el = document.querySelector('[data-testid=frame-counter]');
				const v = Number(el?.textContent);
				const seen: number[] = (window as any).__frames;
				if (el && seen[seen.length - 1] !== v) seen.push(v);
			}).observe(document.documentElement, { subtree: true, childList: true, characterData: true });
		});
	});
	await page.goto(`${BASE}/verify`);
	await expect(page.getByRole('heading', { level: 1 })).toContainText('검증');

	// 1) 패리티: 단계 3개 x 정밀도 2개, 사례 수 > 0, 실패 0
	const sections = page.getByTestId('step-section');
	await expect(sections).toHaveCount(3);
	const summaries = page.getByTestId('parity-summary');
	await expect(summaries).toHaveCount(6, { timeout: 30_000 });
	for (const s of await summaries.all()) {
		await expect.poll(async () => Number(await s.getAttribute('data-cases')), { timeout: 30_000 }).toBeGreaterThan(0);
		await expect(s).toHaveAttribute('data-failures', '0');
	}
	expect(await page.getByTestId('parity-row').count()).toBeGreaterThan(40);
	expect(await page.locator('tr.fail').count()).toBe(0);

	// 2) 함수/조작 값/대안 소스가 보임
	expect(await page.getByTestId('fn-row').count()).toBeGreaterThan(20);
	expect(await page.getByTestId('param-row').count()).toBeGreaterThan(20);
	const alts = page.getByTestId('alt-source');
	await expect(alts).toHaveCount(10); // 4 + 3 + 3
	for (const a of await alts.all()) {
		await expect(a).toBeVisible();
		expect((await a.textContent())!.trim().length).toBeGreaterThan(20);
	}
	await expect(alts.first()).toContainText('power_balance_derivative');

	// 3) 그림: 1, 2단계 canvas, 3단계 라이브 canvas에 색 있는 픽셀이 있다
	// 속도는 화면에서 km/h로 보인다 (계산은 m/s, 목록 파일의 display.scale = 3.6으로 바꿔 표시)
	const note1 = page.getByTestId('plot-note-1');
	await expect(note1).toContainText('닫힘 323.5 km/h', { timeout: 30_000 });
	await expect(note1).toContainText('열림 336.5 km/h');
	await expect(note1).toContainText('DRS 이득 13.0 km/h');
	await expect(page.getByTestId('param-row').filter({ hasText: /^v0/ }).first()).toContainText('km/h');
	await expect(page.getByTestId('plot-note-2')).toContainText('적응형', { timeout: 30_000 });
	await expect(page.getByTestId('step3-status')).toHaveText('완료', { timeout: 30_000 });
	await expect(page.getByTestId('frame-counter')).toHaveText('30');
	for (const id of ['plot-1', 'plot-2', 'plot-3-live']) {
		const px = await pixels(page, id);
		expect(px.nonBg, id).toBeGreaterThan(300);
		expect(px.colored, id).toBeGreaterThan(50);
	}
	// 2단계: 적응형 걸음이 t_open 부근에서 줄어든다는 문장 (최소 Δt < 최대 Δt)
	const note2 = (await page.getByTestId('plot-note-2').textContent())!;
	const [, maxDt, minDt] = note2.match(/최대 Δt ([\d.]+) s.*최소 Δt ([\d.]+) s/)!;
	expect(Number(minDt)).toBeLessThan(Number(maxDt));

	// 4) 3단계 Worker: 중간 프레임이 도착했다
	const seen: number[] = await page.evaluate(() => (window as any).__frames);
	expect(seen[seen.length - 1]).toBe(30);
	expect(seen.filter((n) => n > 0 && n < 30).length).toBeGreaterThanOrEqual(3);
	expect(seen.slice(1)).toEqual([...seen.slice(1)].sort((a, b) => a - b));
	expect(page.workers().length).toBeGreaterThan(0);

	// 5) 적분기와 정밀도를 바꾸면 결과가 바뀐다
	const err = page.getByTestId('step3-error');
	// 그린 곡선이 실제 현재 장인지: 화면에서 다시 계산한 (그린 값 - 해석해) 최대 차이가
	// 커널이 보고한 오차와 같아야 한다. 옛 장(초기조건)을 그리면 차이가 1에 가까워져 실패한다.
	const plotMatchesKernel = async (tol: number) => {
		const kernel = Number(await err.textContent());
		const drawn = Number(await page.getByTestId('step3-plot-error').textContent());
		expect(drawn).toBeLessThan(0.05);
		expect(Math.abs(drawn - kernel)).toBeLessThanOrEqual(tol * Math.max(kernel, 1e-12));
	};
	const settle = async (tol: number) => {
		await expect(page.getByTestId('step3-status')).toHaveText('완료', { timeout: 30_000 });
		await expect(page.getByTestId('frame-counter')).toHaveText('30');
		await plotMatchesKernel(tol);
		return (await err.textContent())!;
	};
	await plotMatchesKernel(1e-5);
	const euler64 = await err.textContent();
	await page.getByTestId('integrator').selectOption('3'); // Crank–Nicolson
	await expect(err).not.toHaveText(euler64!);
	const cn64 = await settle(1e-5);
	expect(cn64).not.toBe(euler64);
	await page.getByTestId('precision').selectOption('f32');
	await expect(err).not.toHaveText(cn64);
	const cn32 = await settle(1e-2);
	expect(cn32).not.toBe(cn64);
	expect(Number(cn32)).toBeGreaterThan(0);
	expect((await pixels(page, 'plot-3-live')).colored).toBeGreaterThan(50);

	// 6) WASM 요청이 사이트 기준 경로 아래에서 나갔다 (메인 스레드 + Worker 모두)
	expect(w.wasmUrls.length).toBeGreaterThanOrEqual(4);
	for (const u of w.wasmUrls) expect(u.startsWith(`${BASE}/wasm/step`)).toBe(true);

	// 그림은 따로도 저장한다: 전체 화면 캡처는 길어서 사람이 그림을 읽기 어렵다.
	for (const id of ['plot-1', 'plot-2', 'plot-3-live'])
		await page.getByTestId(id).screenshot({ path: `${SHOTS}/${PREFIX}${id}.png` });
	await page.screenshot({ path: `${SHOTS}/${PREFIX}verify.png`, fullPage: true });
	await expect(page.getByTestId('error')).toHaveCount(0);
	expect(w.problems).toEqual([]);
});
