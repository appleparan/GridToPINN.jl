import type { Precision, Step } from './types';

type Typed = Float64Array | Float32Array;

/** WASM vec 참조를 타입 배열로 읽는다 (vec_len/vec_get을 원소별로 호출; 1-기반 인덱스). */
export function readVector(step: Step, vec: unknown, precision: Precision, out?: Typed): Typed {
	const n = step.fn('vec_len', precision)(vec) as number;
	const get = step.fn('vec_get', precision);
	const dst = out && out.length === n ? out : precision === 'f64' ? new Float64Array(n) : new Float32Array(n);
	for (let i = 0; i < n; i++) dst[i] = get(vec, i + 1);
	return dst;
}

/** 값들로 WASM vec을 만든다. */
export function writeVector(step: Step, values: ArrayLike<number>, precision: Precision): unknown {
	const v = step.fn('vec_new', precision)(values.length);
	const set = step.fn('vec_set', precision);
	for (let i = 0; i < values.length; i++) set(v, i + 1, values[i]);
	return v;
}
