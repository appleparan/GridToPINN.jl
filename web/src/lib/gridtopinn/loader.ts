import type { FetchFn, Manifest, ParityCase, Precision, Step, WasmExports, WasmIndex } from './types';

/** 호출 시점에 전역 fetch를 찾는다 (모듈 최상단에서 접근하지 않음 — 사전 렌더링 안전). */
const defaultFetch: FetchFn = (url) => fetch(url);

const join = (baseUrl: string, name: string) => `${baseUrl.replace(/\/+$/, '')}/${name}`;

async function getOk(url: string, fetchFn: FetchFn) {
	const res = await fetchFn(url);
	if (!res.ok) throw new Error(`GET ${url} 실패: HTTP ${res.status}`);
	return res;
}

/** baseUrl: 산출물이 있는 디렉터리 URL (예: `${base}/wasm`). */
export async function loadIndex(baseUrl: string, fetchFn: FetchFn = defaultFetch): Promise<WasmIndex> {
	const res = await getOk(join(baseUrl, 'index.json'), fetchFn);
	return (await res.json()) as WasmIndex;
}

export async function loadStep(baseUrl: string, step: number, fetchFn: FetchFn = defaultFetch): Promise<Step> {
	const index = await loadIndex(baseUrl, fetchFn);
	const entry = index.steps.find((s) => s.step === step);
	if (!entry) throw new Error(`index.json에 step ${step}이 없다`);
	const manifest = (await (await getOk(join(baseUrl, entry.manifest), fetchFn)).json()) as Manifest;
	const bytes = await (await getOk(join(baseUrl, entry.wasm), fetchFn)).arrayBuffer();
	const { instance } = await WebAssembly.instantiate(bytes, {});
	const exports = instance.exports as unknown as WasmExports;
	const byName = new Map(manifest.functions.map((f) => [f.name, f]));
	return {
		manifest,
		exports,
		fn(name: string, precision: Precision) {
			const spec = byName.get(name);
			if (!spec) throw new Error(`step ${step}에 함수 '${name}'이 없다 (있는 것: ${[...byName.keys()].join(', ')})`);
			const exportName = spec.exports[precision];
			const f = exportName === undefined ? undefined : exports[exportName];
			if (typeof f !== 'function') throw new Error(`export '${exportName}'(${name}, ${precision})을 모듈에서 찾지 못했다`);
			return f;
		}
	};
}

export async function loadParity(baseUrl: string, step: number, fetchFn: FetchFn = defaultFetch): Promise<ParityCase[]> {
	const index = await loadIndex(baseUrl, fetchFn);
	const entry = index.steps.find((s) => s.step === step);
	if (!entry) throw new Error(`index.json에 step ${step}이 없다`);
	return (await (await getOk(join(baseUrl, entry.parity), fetchFn)).json()) as ParityCase[];
}
