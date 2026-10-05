import { describe, expect, it } from 'vitest';
import { loadIndex, loadParity, loadStep, readVector, runParity, writeVector, type Precision } from '../../src/lib/gridtopinn';
import { BASE_URL, fileFetch } from './helpers';

describe('parity against the real wasm', async () => {
	const index = await loadIndex(BASE_URL, fileFetch);
	it('index lists steps 1-3', () => expect(index.steps.map((s) => s.step)).toEqual([1, 2, 3]));
	for (const entry of index.steps) {
		it(`step ${entry.step}: every parity case passes in f64 and f32`, async () => {
			const step = await loadStep(BASE_URL, entry.step, fileFetch);
			const results = runParity(step, await loadParity(BASE_URL, entry.step, fileFetch));
			for (const p of ['f64', 'f32'] as const) {
				const rs = results.filter((r) => r.precision === p);
				expect(rs.length).toBeGreaterThan(0);
				expect(rs.flatMap((r) => (r.pass ? [] : [`${r.name}: ${JSON.stringify(r.ops.filter((o) => !o.pass))}`]))).toEqual([]);
			}
		});
	}
	it('runParity reports a failure when an expected value is wrong', async () => {
		const step = await loadStep(BASE_URL, 1, fileFetch);
		const cases = await loadParity(BASE_URL, 1, fileFetch);
		const bad = structuredClone(cases);
		const op = bad[0].ops.find((o) => typeof o.expected === 'number')!;
		op.expected = (op.expected as number) * 1.001;
		const r = runParity(step, bad);
		expect(r[0].pass).toBe(false);
		expect(r[0].maxRelDiff).toBeGreaterThan(1e-4);
	});
});

describe('loader', () => {
	it('fn resolves logical names and throws clearly for unknown ones', async () => {
		const step = await loadStep(BASE_URL, 1, fileFetch);
		expect(step.fn('top_speed', 'f64')(600000, 1.225, 0.9, 1.5, 0)).toBeCloseTo(89.8608, 3);
		expect(() => step.fn('nope', 'f64')).toThrow(/'nope'/);
	});
	it('rejects an unknown step and a missing file', async () => {
		await expect(loadStep(BASE_URL, 99, fileFetch)).rejects.toThrow(/step 99/);
		await expect(loadIndex('http://test/wrong', fileFetch)).rejects.toThrow(/404/);
	});
});

describe('arrays', () => {
	for (const p of ['f64', 'f32'] as Precision[]) {
		it(`writeVector/readVector round trip (${p})`, async () => {
			const step = await loadStep(BASE_URL, 3, fileFetch);
			const values = [0.5, -2, 3.25, 1e3];
			const out = readVector(step, writeVector(step, values, p), p);
			expect(out).toBeInstanceOf(p === 'f64' ? Float64Array : Float32Array);
			expect(Array.from(out)).toEqual(values);
		});
	}
});
