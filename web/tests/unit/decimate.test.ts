// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { decimate } from '../../src/lib/ui/plot/decimate';

describe('decimate', () => {
	it('returns short series unchanged', () => {
		expect(decimate([0, 1, 2], [5, 6, 7], 10)).toEqual({ x: [0, 1, 2], y: [5, 6, 7] });
	});
	it('thins long series, keeping first, last, the spike and the non-finite sample', () => {
		const n = 10_000;
		const x = Array.from({ length: n }, (_, i) => i);
		const y = x.map(() => 1);
		y[4321] = 99;
		y[7000] = NaN;
		const d = decimate(x, y, 400);
		expect(d.x.length).toBeLessThan(600);
		expect(d.x[0]).toBe(0);
		expect(d.x[d.x.length - 1]).toBe(n - 1);
		expect(d.x).toContain(4321);
		expect(Math.max(...d.y.filter(Number.isFinite))).toBe(99);
		expect(d.y.some(Number.isNaN)).toBe(true);
		expect([...d.x].sort((a, b) => a - b)).toEqual(d.x);
	});
});
