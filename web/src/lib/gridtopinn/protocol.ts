// Worker 메시지 형식. GC 참조(sim, vec 등)는 양쪽에서 { handle: number }로 표현하고,
// 실제 참조는 Worker 안의 핸들 표에만 있다.
import type { Precision } from './types';

export interface Handle {
	handle: number;
}
export type Arg = number | Handle;
export interface CallSpec {
	fn: string;
	args: Arg[];
}
export type TypedVec = Float64Array | Float32Array;

export type Request =
	| { id: number; op: 'load'; baseUrl: string; step: number }
	| ({ id: number; op: 'call'; precision: Precision } & CallSpec)
	| { id: number; op: 'read'; handle: number; precision: Precision }
	| { id: number; op: 'release'; handles: number[] }
	| {
			id: number;
			op: 'run';
			precision: Precision;
			fn: string;
			args: Arg[];
			frames: number;
			/** 매 프레임 뒤에 읽을 vec: 핸들, 또는 매번 호출해 얻는 vec */
			vectors?: (Handle | CallSpec)[];
			/** 매 프레임 뒤에 평가할 스칼라 함수 */
			scalars?: CallSpec[];
	  }
	| { id: number; op: 'stop'; target: number };

/** 호출 결과: 숫자는 그대로, GC 참조는 { handle } */
export type Value = number | Handle;

export type Response =
	| { id: number; type: 'ok'; result?: Value | TypedVec | { manifest: unknown } | { frames: number; stopped: boolean } }
	| { id: number; type: 'frame'; frame: number; result: Value; vectors: TypedVec[]; scalars: number[] }
	| { id: number; type: 'error'; message: string };
