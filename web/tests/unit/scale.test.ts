import { describe, expect, test } from 'vitest';
import { SLIDER_STEPS, clamp, fromPosition, parseInput, pickScale, toPosition, type SliderWindow } from '../../src/lib/ui/controls/scale';

const lin: SliderWindow = { min: 0, max: 300, kind: 'linear', integer: false };
const log: SliderWindow = { min: 1e-9, max: 0.1, kind: 'log', integer: false };
const int: SliderWindow = { min: 8, max: 400, kind: 'linear', integer: true };

describe('pickScale', () => {
	test('log when positive and spanning three decades', () => expect(pickScale(1e-9, 0.1)).toBe('log'));
	test('linear when the range includes zero', () => expect(pickScale(0, 20000)).toBe('linear'));
	test('linear when the ratio is below 1000', () => expect(pickScale(0.1, 10)).toBe('linear'));
});
describe('position mapping', () => {
	test('ends map exactly', () => {
		for (const w of [lin, log, int]) {
			expect(fromPosition(0, w)).toBe(w.min);
			expect(fromPosition(SLIDER_STEPS, w)).toBe(w.max);
			expect(toPosition(w.min, w)).toBe(0);
			expect(toPosition(w.max, w)).toBe(SLIDER_STEPS);
		}
	});
	test('log midpoint is the geometric mean', () => expect(fromPosition(SLIDER_STEPS / 2, log)).toBeCloseTo(1e-5, 12));
	test('round trip stays within one slider step', () => {
		for (const w of [lin, log]) for (const pos of [1, 137, 500, 999]) expect(Math.abs(toPosition(fromPosition(pos, w), w) - pos)).toBeLessThanOrEqual(1);
	});
	test('integer windows return integers', () => expect(Number.isInteger(fromPosition(333, int))).toBe(true));
	test('out-of-window values clamp', () => {
		expect(toPosition(-5, lin)).toBe(0);
		expect(toPosition(1, log)).toBe(SLIDER_STEPS);
		expect(clamp(1e9, int)).toBe(400);
	});
});
describe('parseInput', () => {
	test('converts display units to SI', () => expect(parseInput('180', 3.6, lin)).toBeCloseTo(50, 12));
	test('accepts exponent notation', () => expect(parseInput('2e-3', 1, log)).toBe(2e-3));
	test('clamps to the window', () => expect(parseInput('99999', 1, lin)).toBe(300));
	test('rounds integer windows', () => expect(parseInput('100.6', 1, int)).toBe(101));
	test.each(['', '   ', 'abc', 'NaN', 'Infinity'])('rejects %j', (s) => expect(parseInput(s, 1, lin)).toBeUndefined());
});
