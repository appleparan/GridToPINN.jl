import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { CURRICULUM } from '../../src/lib/curriculum';
import { EXPERIMENTS, findParam, initialValues, windowOf } from '../../src/lib/experiments/config';
import type { Manifest, WasmIndex } from '../../src/lib/gridtopinn/types';

const read = <T>(f: string) => JSON.parse(readFileSync(`static/wasm/${f}`, 'utf8')) as T;
const index = read<WasmIndex>('index.json');

test('curriculum lists nine steps in order', () => expect(CURRICULUM.map((s) => s.step)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9]));
describe.each(index.steps)('step $step', (entry) => {
	const m = read<Manifest>(entry.manifest);
	const cfg = EXPERIMENTS[entry.step];
	test('has an experiment config', () => expect(cfg).toBeDefined());
	test('curriculum title and question match the manifest', () => {
		const c = CURRICULUM.find((s) => s.step === entry.step)!;
		expect(c.title).toBe(m.title);
		expect(c.question).toBe(m.question);
	});
	test('alternative exists in the manifest', () => expect(m.alternatives.some((a) => a.id === cfg.alternative)).toBe(true));
	test.each(cfg.controls)('control $name is inside the manifest range', (c) => {
		const p = findParam(m, c.name);
		const w = windowOf(p, c);
		expect(w.min).toBeGreaterThanOrEqual(p.min);
		expect(w.max).toBeLessThanOrEqual(p.max);
		expect(w.min).toBeLessThan(w.max);
		const v = initialValues(m, cfg)[c.name];
		expect(v).toBeGreaterThanOrEqual(w.min);
		expect(v).toBeLessThanOrEqual(w.max);
	});
});
test('findParam throws on an unknown name', () => expect(() => findParam(read<Manifest>('step1.json'), 'nope')).toThrow());
