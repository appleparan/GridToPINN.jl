// 연결 모듈의 공용 타입. 스키마는 wasm/spec.jl이 쓰는 매니페스트(schema 1)와 같다.

export type Precision = 'f64' | 'f32';
export const PRECISIONS: readonly Precision[] = ['f64', 'f32'];

export interface IndexStep {
	step: number;
	title: string;
	manifest: string;
	wasm: string;
	parity: string;
	bytes: number;
}
export interface WasmIndex {
	schema: number;
	generated_with: { julia: string; wasmtarget: string };
	steps: IndexStep[];
}

export interface SourceRange {
	file: string;
	lines: [number, number];
}
export interface FnArg {
	name: string;
	type: string;
}
/** 화면 표시 단위: 표시값 = 값 × scale. 계산과 WASM 인자는 항상 SI다. */
export interface DisplayUnit {
	unit: string;
	scale: number;
}
export interface FnSpec {
	name: string;
	/** 반환값의 표시 단위 (없으면 그대로 보인다) */
	display?: DisplayUnit | null;
	exports: Record<Precision, string>;
	args: FnArg[];
	returns: string;
	doc: string;
	source: SourceRange;
}
export interface ParamSpec {
	name: string;
	unit: string;
	default: number;
	min: number;
	max: number;
	doc: string;
	used_by: string[];
	/** 표시 단위 (없으면 unit 그대로 보인다) */
	display?: DisplayUnit | null;
	source?: SourceRange;
	presets?: { label: string; value: number }[];
}
export interface AltOption {
	value: number;
	key: string;
	label: string;
	source: SourceRange;
}
export interface AltSpec {
	id: string;
	title: string;
	arg: string;
	used_by?: string[];
	options: AltOption[];
}
export interface Manifest {
	schema: number;
	step: number;
	title: string;
	question: string;
	wasm: string;
	precisions: Precision[];
	functions: FnSpec[];
	parameters: ParamSpec[];
	alternatives: AltSpec[];
	requirements: string[];
	limits: string[];
}

/** 패리티 파일에서 숫자 또는 "NaN"/"Infinity"/"-Infinity" 문자열 */
export type JsonNumber = number | 'NaN' | 'Infinity' | '-Infinity';
export interface ParityOp {
	fn: string;
	args: (JsonNumber | string)[]; // "$name"은 앞선 op의 bind 참조
	bind?: string;
	expected?: JsonNumber;
}
export interface ParityCase {
	name: string;
	precision: Precision;
	ops: ParityOp[];
}

/** WASM 모듈의 export 모음. GC 참조는 불투명 값(unknown)이다. */
export type WasmExports = Record<string, (...args: any[]) => any>;

export type FetchFn = (url: string) => Promise<{
	ok: boolean;
	status: number;
	json(): Promise<unknown>;
	arrayBuffer(): Promise<ArrayBuffer>;
}>;

export interface Step {
	manifest: Manifest;
	exports: WasmExports;
	/** 논리 이름 + 정밀도 -> export 함수. 모르는 이름은 예외. */
	fn(name: string, precision: Precision): (...args: any[]) => any;
}
