import type { JsonNumber, ParityCase, Step } from './types';

export const TOLERANCE = { f64: 1e-12, f32: 1e-5 } as const;
const ABS_FLOOR = 1e-300;
const SPECIAL: Record<string, number> = { NaN: NaN, Infinity: Infinity, '-Infinity': -Infinity };

export const decode = (x: JsonNumber | string): number | string =>
	typeof x === 'string' && x in SPECIAL ? SPECIAL[x] : x;

/** NaN끼리, 부호가 같은 무한대끼리는 같다(0). 그 밖에는 상대오차. */
export function relDiff(actual: number, expected: number): number {
	if (Number.isNaN(expected) || Number.isNaN(actual)) return Number.isNaN(expected) && Number.isNaN(actual) ? 0 : Infinity;
	if (!Number.isFinite(expected) || !Number.isFinite(actual)) return actual === expected ? 0 : Infinity;
	return Math.abs(actual - expected) / Math.max(Math.abs(expected), ABS_FLOOR);
}

export interface OpResult {
	fn: string;
	actual: number;
	expected: number;
	relDiff: number;
	pass: boolean;
}
export interface CaseResult {
	name: string;
	precision: 'f64' | 'f32';
	ops: OpResult[];
	pass: boolean;
	maxRelDiff: number;
}

export function runParity(step: Step, cases: ParityCase[]): CaseResult[] {
	return cases.map((c) => {
		const env: Record<string, unknown> = {};
		const ops: OpResult[] = [];
		for (const op of c.ops) {
			const args = op.args.map((a) => (typeof a === 'string' && a.startsWith('$') ? env[a.slice(1)] : decode(a)));
			const result = step.fn(op.fn, c.precision)(...args);
			if (op.bind) env[op.bind] = result;
			if (op.expected === undefined) continue;
			const expected = decode(op.expected) as number;
			const d = relDiff(result as number, expected);
			ops.push({ fn: op.fn, actual: result as number, expected, relDiff: d, pass: d <= TOLERANCE[c.precision] });
		}
		const finite = ops.map((o) => o.relDiff).filter(Number.isFinite);
		return {
			name: c.name,
			precision: c.precision,
			ops,
			pass: ops.every((o) => o.pass),
			maxRelDiff: finite.length ? Math.max(...finite) : 0
		};
	});
}
