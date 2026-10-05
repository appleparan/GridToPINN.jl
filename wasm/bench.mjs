// bench.mjs — WASM 쪽 비용을 잰다. (a) 벡터를 vec_get으로 하나씩 읽기, (b) vec_set으로 쓰기, (c) 대표 커널 실행 시간.
//   node wasm/bench.mjs      (먼저 julia +1.12 --project=wasm wasm/build.jl)
// 같은 커널의 네이티브 시간은 julia +1.12 --project=wasm wasm/bench.jl 로 잰다.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../web/static/wasm');
const load = async (n) => (await WebAssembly.instantiate(fs.readFileSync(path.join(dir, `step${n}.wasm`)), {})).instance.exports;
const [s1, s2, s3] = [await load(1), await load(2), await load(3)];

const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];
function time(fn, reps) {
	fn(); // 워밍업
	const t = [];
	for (let i = 0; i < reps; i++) {
		const t0 = performance.now();
		fn();
		t.push(performance.now() - t0);
	}
	return median(t);
}

console.log('Vector bridge: one vec_get / vec_set call per element (median ms; ns per element)');
console.log('       n   read f64   write f64   read f32   write f32     ns/elt (read f64)');
for (let p = 8; p <= 20; p += 2) {
	const n = 2 ** p;
	const row = [];
	for (const [sfx, Arr] of [['f64', Float64Array], ['f32', Float32Array]]) {
		const v = s1[`vec_new_${sfx}`](n);
		const get = s1[`vec_get_${sfx}`];
		const set = s1[`vec_set_${sfx}`];
		const out = new Arr(n);
		const src = Arr.from({ length: n }, (_, i) => i * 0.5);
		const reps = n >= 2 ** 18 ? 5 : 15;
		row.push(time(() => { for (let i = 0; i < n; i++) out[i] = get(v, i + 1); }, reps));
		row.push(time(() => { for (let i = 0; i < n; i++) set(v, i + 1, src[i]); }, reps));
	}
	const f = (x) => x.toFixed(3).padStart(10);
	console.log(String(n).padStart(8), f(row[0]), f(row[1]), f(row[2]), f(row[3]), ((row[0] * 1e6) / n).toFixed(1).padStart(14));
}

console.log('\nKernels (median ms per call, f64 | f32)');
const kernels = [
	['step1 top_speed (x1000 calls)', (s) => () => { for (let i = 0; i < 1000; i++) s1[`top_speed_${s}`](600e3, 1.225, 0.9, 1.5, 0); }, 15],
	['step2 drs_run rk4, dt=0.01, t_end=80 (8000 steps)', (s) => () => s2[`drs_run_${s}`](2, 0.01, 1e-6, 600e3, 800, 1.225, 1.5, 0, 0.9, 0.8, 20, 80), 15],
	['step3 advance rk4, N=200, 1000 steps', (s) => { const sim = s3[`moving_wall_${s}`](200, 0.1, 1, 1e-6); return () => s3[`advance_${s}`](sim, 1e-3, 1000, 2); }, 7],
];
for (const [label, make, reps] of kernels) {
	console.log(label.padEnd(52), time(make('f64'), reps).toFixed(3).padStart(10), '|', time(make('f32'), reps).toFixed(3).padStart(10));
}
