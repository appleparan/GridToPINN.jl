// check_parity.mjs — 모든 단계의 .wasm을 Node에서 실행해 패리티 사례를 expected와 비교한다.
//   node wasm/check_parity.mjs        (먼저 julia +1.12 --project=wasm wasm/build.jl)
// 의존 패키지 없음. 어긋나는 값이 하나라도 있으면 종료 코드 1.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../web/static/wasm');
const TOL = { f64: 1e-12, f32: 1e-5 };
const ABS_FLOOR = 1e-300;
const SPECIAL = { NaN: NaN, Infinity: Infinity, '-Infinity': -Infinity };
const decode = (x) => (typeof x === 'string' && x in SPECIAL ? SPECIAL[x] : x);

// NaN끼리, 부호가 같은 무한대끼리는 같다. 그 밖에는 상대오차.
function relDiff(actual, expected) {
	if (Number.isNaN(expected) || Number.isNaN(actual)) return Number.isNaN(expected) && Number.isNaN(actual) ? 0 : Infinity;
	if (!Number.isFinite(expected) || !Number.isFinite(actual)) return actual === expected ? 0 : Infinity;
	return Math.abs(actual - expected) / Math.max(Math.abs(expected), ABS_FLOOR);
}

const index = JSON.parse(fs.readFileSync(path.join(dir, 'index.json'), 'utf8'));
let failures = 0;
const maxRel = { f64: 0, f32: 0 };

for (const s of index.steps) {
	const bytes = fs.readFileSync(path.join(dir, s.wasm));
	const { instance } = await WebAssembly.instantiate(bytes, {});
	const ex = instance.exports;
	const cases = JSON.parse(fs.readFileSync(path.join(dir, s.parity), 'utf8'));
	let ops = 0;
	let bad = 0;
	for (const c of cases) {
		const env = {};
		for (const op of c.ops) {
			const args = op.args.map((a) => (typeof a === 'string' && a.startsWith('$') ? env[a.slice(1)] : decode(a)));
			const result = ex[`${op.fn}_${c.precision}`](...args);
			if (op.bind) env[op.bind] = result;
			if (op.expected === undefined) continue;
			ops++;
			const expected = decode(op.expected);
			const d = relDiff(result, expected);
			if (Number.isFinite(d)) maxRel[c.precision] = Math.max(maxRel[c.precision], d);
			if (!(d <= TOL[c.precision])) {
				bad++;
				console.log(`  MISMATCH [${c.precision}] ${c.name}: ${op.fn}(${op.args.join(', ')}) = ${result}, expected ${expected} (rel ${d})`);
			}
		}
	}
	failures += bad;
	const imports = WebAssembly.Module.imports(await WebAssembly.compile(bytes)).length;
	console.log(`step${s.step}: ${cases.length} cases, ${ops} compared ops, ${bad} mismatches, ${imports} imports`);
}
console.log(`max relative difference: f64 ${maxRel.f64.toExponential(2)}, f32 ${maxRel.f32.toExponential(2)}`);
process.exit(failures ? 1 : 0);
