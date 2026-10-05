// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { revealCount, revealUpTo } from '../../src/lib/experiments/reveal';

describe('revealUpTo', () => {
	it('returns empty for empty input', () => {
		expect(revealUpTo([], [], 1)).toEqual({ x: [], y: [], last: -1 });
	});
	it('returns empty when the cut is before the first sample', () => {
		expect(revealUpTo([1, 2], [10, 20], 0.5)).toEqual({ x: [], y: [], last: -1 });
	});
	it('returns everything, with no extra point, when the cut is beyond the last sample', () => {
		expect(revealUpTo([0, 1, 2], [0, 10, 20], 5)).toEqual({ x: [0, 1, 2], y: [0, 10, 20], last: 2 });
	});
	it('does not duplicate a point when the cut sits exactly on a sample', () => {
		expect(revealUpTo([0, 1, 2], [0, 10, 20], 1)).toEqual({ x: [0, 1], y: [0, 10], last: 1 });
	});
	it('adds one linearly interpolated point mid-interval', () => {
		const r = revealUpTo([0, 1, 3], [0, 10, 30], 2);
		expect(r.x).toEqual([0, 1, 2]);
		expect(r.y).toEqual([0, 10, 20]);
		// the interpolated head is not a sample: `last` points at the real one before it
		expect(r.last).toBe(1);
		expect(r.y[r.last]).toBe(10);
	});
	it('does not interpolate across a non-finite bracketing sample', () => {
		expect(revealUpTo([0, 1, 2], [0, 10, NaN], 1.5)).toEqual({ x: [0, 1], y: [0, 10], last: 1 });
		expect(revealUpTo([0, 1, 2], [0, NaN, 20], 1.5)).toEqual({ x: [0, 1], y: [0, NaN], last: 1 });
	});
	it('accepts typed arrays', () => {
		expect(revealUpTo(new Float64Array([0, 2]), new Float64Array([0, 4]), 1).y).toEqual([0, 2]);
	});
});

describe('revealCount', () => {
	it('takes the first `count` samples', () => {
		expect(revealCount([0, 1, 2], [5, 6, 7], 2)).toEqual({ x: [0, 1], y: [5, 6] });
	});
	it('clamps count to [0, length]', () => {
		expect(revealCount([0, 1], [5, 6], -3)).toEqual({ x: [], y: [] });
		expect(revealCount([0, 1], [5, 6], 9)).toEqual({ x: [0, 1], y: [5, 6] });
	});
	it('handles empty input', () => {
		expect(revealCount([], [], 3)).toEqual({ x: [], y: [] });
	});
});
